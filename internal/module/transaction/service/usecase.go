package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/module/transaction/repository"
	"mbanking-bpr/internal/notification"
	"mbanking-bpr/internal/ownership"
	"mbanking-bpr/pkg/logger"
	"mbanking-bpr/pkg/money"
	"mbanking-bpr/pkg/security"

	"github.com/google/uuid"
)

const (
	maxPINAttempts = 3
	cbsCallTimeout = 30 * time.Second
)

var (
	ErrIdempotencyKeyRequired = rejected("header Idempotency-Key wajib disertakan (8-80 karakter alfanumerik)")
	ErrIdempotencyConflict    = errors.New("Idempotency-Key sudah digunakan untuk transaksi dengan data berbeda")
	ErrTransferInProgress     = errors.New("transaksi dengan Idempotency-Key ini sedang diproses atau menunggu rekonsiliasi. Jangan ulangi transfer")
	ErrInterbankUnsupported   = rejected("transfer antarbank belum tersedia di Mobile DMB")
	ErrInvalidAmount          = rejected("nominal transfer tidak valid (harus bilangan bulat rupiah)")
	ErrInvalidDestination     = rejected("nomor rekening tujuan tidak valid")
	ErrSourceNotOwned         = ownership.ErrNotOwned
	ErrPINNotSet              = rejected("PIN transaksi belum diatur. Silakan selesaikan aktivasi terlebih dahulu")
	ErrWeakPINInUse           = rejected("PIN transaksi Anda terlalu mudah ditebak/bawaan. Demi keamanan, silakan ganti PIN terlebih dahulu")
	ErrServiceUnavailable     = errors.New("layanan transaksi sedang tidak tersedia, silakan coba beberapa saat lagi")
	// ErrOutcomeUnknown is returned when CBS did not confirm the result. The request stays
	// in UNKNOWN status for reconciliation and must not be retried by the customer.
	ErrOutcomeUnknown = errors.New("Status transaksi sedang diverifikasi. Mohon periksa kembali riwayat transaksi dan jangan mengulang transfer. Bila saldo terpotong tanpa bukti transaksi, hubungi CS Bank DMB dengan nomor referensi berikut")
)

// Business defaults used only when the app_configs row does not set a value.
var (
	maxTransferAmount  = money.Rupiah(1_000_000_000_000) // sanity cap (Rp 1 triliun)
	defaultMinTransfer = money.Rupiah(10_000)
	defaultDailyLimit  = money.Rupiah(25_000_000)
)

var (
	idemKeyPattern = regexp.MustCompile(`^[A-Za-z0-9_\-]{8,80}$`)
	accountPattern = regexp.MustCompile(`^[0-9]{6,30}$`)
)

// ErrRejected marks validation / business-rule rejections whose message is safe to
// show to the customer (no funds were moved). Any other error is treated as an
// internal failure by the handler and replaced by a generic message.
var ErrRejected = errors.New("transaksi ditolak")

type rejection struct{ msg string }

func (r *rejection) Error() string        { return r.msg }
func (r *rejection) Is(target error) bool { return target == ErrRejected }

func rejected(msg string) error { return &rejection{msg: msg} }

// TransferInput is a transfer request plus the verified caller context.
type TransferInput struct {
	UserID         string
	CIF            string
	TokenAccount   string
	DeviceID       string
	IdempotencyKey string
	Request        domain.TransferRequest
}

// TransferResult carries the response and, for unknown outcomes, the reference to quote.
type TransferResult struct {
	Response  *domain.TransferResponse
	RequestID string
}

type TransactionService interface {
	Transfer(ctx context.Context, in TransferInput) (*TransferResult, error)
}

type transactionService struct {
	repo          repository.TransactionRepository
	cbsProv       cbsprovider.CBSProvider
	resolver      *ownership.Resolver
	internalCodes map[string]bool
}

func NewTransactionService(repo repository.TransactionRepository, cbsProv cbsprovider.CBSProvider, resolver *ownership.Resolver, internalBankCodes []string) TransactionService {
	codes := map[string]bool{}
	for _, c := range internalBankCodes {
		codes[strings.ToUpper(strings.TrimSpace(c))] = true
	}
	return &transactionService{repo: repo, cbsProv: cbsProv, resolver: resolver, internalCodes: codes}
}

func requestHash(from string, r domain.TransferRequest) string {
	s := strings.Join([]string{from, strings.TrimSpace(r.ToAccount), strings.ToUpper(strings.TrimSpace(r.ToBankCode)),
		r.Amount.Decimal2(), strings.TrimSpace(r.Note)}, "|")
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

// Transfer executes an internal (overbooking) transfer with banking controls (audit DMB-004, DMB-015):
// server-side source-account ownership, PIN with lockout, idempotency, atomic daily limit,
// and an explicit UNKNOWN state that is never retried automatically.
func (s *transactionService) Transfer(ctx context.Context, in TransferInput) (*TransferResult, error) {
	req := in.Request

	// 1. Input validation
	if !idemKeyPattern.MatchString(in.IdempotencyKey) {
		return nil, ErrIdempotencyKeyRequired
	}
	// Exact whole-rupiah amount: no fractions, NaN/Inf, negatives or overflow (pkg/money).
	if err := money.ValidateTransferAmount(req.Amount, 0, maxTransferAmount); err != nil {
		return nil, ErrInvalidAmount
	}
	bankCode := strings.ToUpper(strings.TrimSpace(req.ToBankCode))
	if !s.internalCodes[bankCode] {
		return nil, ErrInterbankUnsupported
	}
	req.ToBankCode = "DMB" // normalized internal code understood by every provider
	req.ToAccount = strings.TrimSpace(req.ToAccount)
	if !accountPattern.MatchString(req.ToAccount) {
		return nil, ErrInvalidDestination
	}
	if len(req.Note) > 100 {
		req.Note = req.Note[:100]
	}

	// 2. Operational configuration (defaults if the config row is missing)
	minTransfer, dailyLimit := defaultMinTransfer, defaultDailyLimit
	if cfg, err := s.repo.GetAppConfig(ctx); err == nil && cfg != nil {
		if cfg.MaintenanceMode {
			msg := cfg.MaintenanceMessage
			if msg == "" {
				msg = "Layanan transaksi sedang dalam pemeliharaan berkala. Silakan coba beberapa saat lagi."
			}
			return nil, rejected(msg)
		}
		if cfg.MinTransferAmount > 0 {
			minTransfer = cfg.MinTransferAmount
		}
		if cfg.DailyTransferLimit > 0 {
			dailyLimit = cfg.DailyTransferLimit
		}
	}
	if req.Amount < minTransfer {
		return nil, rejected("nominal transfer minimal " + money.FormatIDR(minTransfer))
	}

	// 3. Customer state & PIN (fail-closed: no PIN means no transfer)
	user, err := s.repo.GetUserByID(ctx, in.UserID)
	if err != nil || user == nil {
		return nil, ErrServiceUnavailable
	}
	if !user.IsActive {
		return nil, rejected("akun nasabah sedang diblokir. Hubungi CS Bank DMB")
	}
	if user.PINHash == "" {
		return nil, ErrPINNotSet
	}

	// 4. Source account must belong to the caller (never trust from_account from the client)
	fromAccount, err := s.resolver.ResolveSavingsAccount(ctx, in.UserID, in.CIF, in.TokenAccount, req.FromAccount)
	if err != nil && errors.Is(err, cbsprovider.ErrCBSUnavailable) {
		// Ownership could not be verified because Core Banking is unreachable: no transfer
		// was attempted; tell the customer it is a service disruption, not a refusal.
		return nil, ErrServiceUnavailable
	}
	if err != nil {
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "TRANSFER_SOURCE_NOT_OWNED", req.FromAccount, "DANGER", in.DeviceID, "Percobaan transfer dari rekening yang bukan milik nasabah ditolak")
		return nil, ErrSourceNotOwned
	}
	if fromAccount == req.ToAccount {
		return nil, ErrInvalidDestination
	}
	req.FromAccount = fromAccount

	if !security.CheckPIN(user.PINHash, req.PIN) {
		attempts, blocked, incErr := s.repo.IncrementFailedPIN(ctx, user.ID, maxPINAttempts)
		if incErr != nil {
			return nil, ErrServiceUnavailable
		}
		if blocked {
			audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "AUTO_BLOCK_PIN", fromAccount, "DANGER", in.DeviceID, "Akun diblokir otomatis karena 3x salah memasukkan PIN Transaksi")
			notification.CreateAndPush(ctx, s.repo.DB(), user.ID, "Akun Diblokir: 3x Salah PIN", "Demi keamanan dana Anda, akun Mobile DMB telah dikunci otomatis karena 3x salah memasukkan PIN Transaksi. Hubungi CS Bank DMB.", "SECURITY")
			return nil, rejected("akun Anda diblokir otomatis karena 3x salah memasukkan PIN Transaksi. Silakan hubungi CS Bank DMB")
		}
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "TRANSFER_PIN_FAILED", fromAccount, "WARNING", in.DeviceID, fmt.Sprintf("Salah PIN Transaksi (Percobaan %d/%d)", attempts, maxPINAttempts))
		return nil, fmt.Errorf("%w (Percobaan %d/%d)", cbsprovider.ErrInvalidPIN, attempts, maxPINAttempts)
	}
	if security.IsWeakPIN(req.PIN) {
		// Covers the PIN that was provisioned by default in earlier versions (audit DMB-003).
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "TRANSFER_WEAK_PIN_REFUSED", fromAccount, "WARNING", in.DeviceID, "Transfer ditolak: PIN lemah/bawaan wajib diganti")
		return nil, ErrWeakPINInUse
	}
	if err := s.repo.ResetFailedPIN(ctx, user.ID); err != nil {
		return nil, ErrServiceUnavailable
	}

	// 5. Idempotent, atomic reservation (daily limit enforced under a row lock)
	reservation := &model.TransferRequest{
		ID: uuid.NewString(), UserID: user.ID, IdempotencyKey: in.IdempotencyKey, RequestHash: requestHash(fromAccount, req),
		FromAccount: fromAccount, ToAccount: req.ToAccount, ToBankCode: req.ToBankCode, Amount: req.Amount,
	}
	existing, used, err := s.repo.ReserveTransfer(ctx, reservation, dailyLimit)
	switch {
	case errors.Is(err, repository.ErrDuplicateRequest) && existing != nil:
		return s.replay(existing, reservation.RequestHash)
	case errors.Is(err, repository.ErrDailyLimitExceeded):
		remaining := dailyLimit - used
		if remaining < 0 {
			remaining = 0
		}
		return nil, rejected(fmt.Sprintf("melebihi batas limit transfer harian (%s). Sisa limit Anda hari ini: %s",
			money.FormatIDR(dailyLimit), money.FormatIDR(remaining)))
	case err != nil:
		logger.GetLogger().Error("Reservasi transfer gagal", map[string]interface{}{"error": err.Error()})
		return nil, ErrServiceUnavailable
	}

	// 6. Execute at CBS. The call is detached from client cancellation so a dropped
	//    connection cannot abort an in-flight debit midway.
	cbsCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), cbsCallTimeout)
	defer cancel()
	res, cbsErr := s.cbsProv.ProcessTransfer(cbsCtx, &req, fromAccount)

	if cbsErr != nil {
		status := model.TransferReqFailed
		if errors.Is(cbsErr, cbsprovider.ErrCBSOutcomeUnknown) {
			status = model.TransferReqUnknown
		}
		if err := s.repo.CompleteTransfer(ctx, reservation.ID, status, "", "", cbsErr.Error()); err != nil {
			logger.GetLogger().Error("Gagal memperbarui status transfer", map[string]interface{}{"request_id": reservation.ID, "error": err.Error()})
		}
		if status == model.TransferReqUnknown {
			audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "TRANSFER_OUTCOME_UNKNOWN", req.ToAccount, "DANGER", in.DeviceID,
				fmt.Sprintf("Transfer %s dari %s ke %s menunggu rekonsiliasi CBS (Req: %s)", money.FormatIDR(req.Amount), fromAccount, req.ToAccount, reservation.ID))
			return &TransferResult{RequestID: reservation.ID}, ErrOutcomeUnknown
		}
		audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "TRANSFER_FAILED", req.ToAccount, "WARNING", in.DeviceID,
			fmt.Sprintf("Transfer gagal %s ke %s (Req: %s)", money.FormatIDR(req.Amount), req.ToAccount, reservation.ID))
		return &TransferResult{RequestID: reservation.ID}, cbsErr
	}

	body, _ := json.Marshal(res)
	if err := s.repo.CompleteTransfer(ctx, reservation.ID, model.TransferReqSuccess, res.ReferenceNo, string(body), ""); err != nil {
		logger.GetLogger().Error("Transfer sukses di CBS tetapi status lokal gagal diperbarui — perlu rekonsiliasi", map[string]interface{}{"request_id": reservation.ID, "error": err.Error()})
	}
	if err := s.repo.SaveTransaction(ctx, &model.Transaction{
		ID: uuid.NewString(), UserID: user.ID, FromAccount: res.FromAccount, ToAccount: res.ToAccount, Amount: res.Amount,
		TransactionType: model.TxTransferInternal, Status: model.TxStatusSuccess, CBSReferenceNo: res.ReferenceNo, CreatedAt: res.Timestamp,
	}); err != nil {
		logger.GetLogger().Error("Gagal mencatat riwayat transaksi lokal", map[string]interface{}{"request_id": reservation.ID, "error": err.Error()})
	}

	audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "TRANSFER_SUCCESS", res.ToAccount, "SUCCESS", in.DeviceID,
		fmt.Sprintf("Transfer %s dari %s ke %s Ref: %s (Req: %s)", money.FormatIDR(res.Amount), res.FromAccount, res.ToAccount, res.ReferenceNo, reservation.ID))
	notification.CreateAndPush(ctx, s.repo.DB(), user.ID, "Transfer Dana Berhasil",
		fmt.Sprintf("Transfer sebesar %s ke rekening %s (%s) telah berhasil diproses. No Ref: %s", money.FormatIDR(res.Amount), res.ToAccount, res.ToAccountName, res.ReferenceNo), "TRANSACTION")

	return &TransferResult{Response: res, RequestID: reservation.ID}, nil
}

// replay returns the outcome of a previous request with the same idempotency key.
func (s *transactionService) replay(existing *model.TransferRequest, hash string) (*TransferResult, error) {
	if existing.RequestHash != hash {
		return nil, ErrIdempotencyConflict
	}
	switch existing.Status {
	case model.TransferReqSuccess:
		var res domain.TransferResponse
		if err := json.Unmarshal([]byte(existing.ResponseJSON), &res); err != nil {
			return &TransferResult{RequestID: existing.ID}, ErrTransferInProgress
		}
		return &TransferResult{Response: &res, RequestID: existing.ID}, nil
	case model.TransferReqFailed:
		return &TransferResult{RequestID: existing.ID}, rejected("transaksi dengan Idempotency-Key ini sebelumnya gagal. Buat transaksi baru")
	default:
		return &TransferResult{RequestID: existing.ID}, ErrTransferInProgress
	}
}
