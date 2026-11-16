package repository

import (
	"context"
	"errors"
	"fmt"
	"mbanking-bpr/pkg/money"
	"strings"
	"time"

	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/crypto"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

var (
	// ErrPhoneInUse is returned when a phone number is already bound to another CIF.
	ErrPhoneInUse = errors.New("nomor handphone sudah terdaftar pada nasabah lain")
	// ErrAccountOwnedByOther is returned when an account is linked to a different customer.
	ErrAccountOwnedByOther = errors.New("rekening terhubung dengan nasabah lain")
)

type AuthRepository interface {
	DB() *gorm.DB
	FindByIdentifier(ctx context.Context, identifier string) (*model.User, error)
	FindByCIF(ctx context.Context, cif string) (*model.User, error)
	FindByID(ctx context.Context, id string) (*model.User, error)
	FindPrimaryAccount(ctx context.Context, userID string) (*model.Account, error)
	EnsurePrimaryAccount(ctx context.Context, user *model.User, preferredAccountNo string) (*model.Account, error)
	FindAccountWithUser(ctx context.Context, accountNo string) (*model.Account, *model.User, error)
	PhoneUsedByOtherUser(ctx context.Context, phone, userID string) (bool, error)
	SetActivationCredentials(ctx context.Context, userID, passwordHash, pinHash, phoneNumber, deviceID string) error
	UpdatePasswordHash(ctx context.Context, userID, passwordHash, deviceID string) error
	UpdateOnlyPINHash(ctx context.Context, userID, pinHash string) error
	IncrementFailedLogin(ctx context.Context, userID string, maxAttempts int) (int, bool, error)
	ResetFailedLogin(ctx context.Context, userID string) error
	IncrementFailedPIN(ctx context.Context, userID string, maxAttempts int) (int, bool, error)
	ResetFailedPIN(ctx context.Context, userID string) error
	UpsertCBSUserAndAccount(ctx context.Context, nasabah *domain.CBSNasabahData, bal *domain.BalanceResponse) (*model.User, *model.Account, error)
}

type authRepository struct {
	db *gorm.DB
}

func NewAuthRepository(db *gorm.DB) AuthRepository {
	return &authRepository{db: db}
}

func (r *authRepository) DB() *gorm.DB {
	return r.db
}

// FindByIdentifier finds a customer by exact phone number or exact CIF.
func (r *authRepository) FindByIdentifier(ctx context.Context, identifier string) (*model.User, error) {
	if r.db == nil || strings.TrimSpace(identifier) == "" {
		return nil, gorm.ErrRecordNotFound
	}
	var user model.User
	if err := r.db.WithContext(ctx).
		Where("phone_number = ? OR cif = ?", identifier, identifier).
		First(&user).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *authRepository) FindByCIF(ctx context.Context, cif string) (*model.User, error) {
	if r.db == nil || strings.TrimSpace(cif) == "" {
		return nil, gorm.ErrRecordNotFound
	}
	var user model.User
	if err := r.db.WithContext(ctx).Where("cif = ?", strings.TrimSpace(cif)).First(&user).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *authRepository) FindByID(ctx context.Context, id string) (*model.User, error) {
	if r.db == nil {
		return nil, gorm.ErrRecordNotFound
	}
	var user model.User
	if err := r.db.WithContext(ctx).Where("id = ?", id).First(&user).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *authRepository) FindPrimaryAccount(ctx context.Context, userID string) (*model.Account, error) {
	if r.db == nil {
		return nil, gorm.ErrRecordNotFound
	}
	var account model.Account
	err := r.db.WithContext(ctx).
		Where("user_id = ? AND status = ?", userID, model.AccountStatusActive).
		Order("created_at ASC").
		First(&account).Error
	if err != nil {
		return nil, err
	}
	return &account, nil
}

// pendingPhonePlaceholder is a non-numeric (never routable) value for the unique
// phone column of customers that have not completed activation.
func pendingPhonePlaceholder(cif string) string {
	p := "P-" + cif
	if len(p) > 20 {
		p = p[:20]
	}
	return p
}

// IsPendingPhone reports whether phone is an activation placeholder.
func IsPendingPhone(phone string) bool {
	return strings.HasPrefix(phone, "P-")
}

func deriveAccountNoFromCIF(cif string) string {
	if len(cif) >= 8 {
		return "00101" + cif[len(cif)-8:]
	}
	if cif != "" {
		return "00101" + cif
	}
	return fmt.Sprintf("00101%d", time.Now().Unix()%100000000)
}

func truncateString(s string, max int) string {
	s = strings.TrimSpace(s)
	if len(s) > max {
		return s[:max]
	}
	return s
}

// EnsurePrimaryAccount returns the user's primary account, creating a local
// placeholder record if none exists. An existing account that belongs to a
// different customer is NEVER re-assigned (audit DMB-003).
func (r *authRepository) EnsurePrimaryAccount(ctx context.Context, user *model.User, preferredAccountNo string) (*model.Account, error) {
	if r.db == nil || user == nil {
		return nil, gorm.ErrInvalidDB
	}
	if existing, err := r.FindPrimaryAccount(ctx, user.ID); err == nil && existing != nil {
		return existing, nil
	}
	accNo := preferredAccountNo
	if accNo == "" || accNo == user.CIF {
		accNo = deriveAccountNoFromCIF(user.CIF)
	}
	var acc model.Account
	if err := r.db.WithContext(ctx).Where("account_number = ?", accNo).First(&acc).Error; err == nil {
		if acc.UserID != user.ID {
			return nil, ErrAccountOwnedByOther
		}
		return &acc, nil
	}
	now := time.Now()
	newAcc := model.Account{
		ID: uuid.NewString(), UserID: user.ID, AccountNumber: accNo, HolderName: user.FullName,
		ProductCode: "01", AccountType: "Tabungan Mandiri DMB", Status: model.AccountStatusActive,
		CreatedAt: now, UpdatedAt: now,
	}
	if err := r.db.WithContext(ctx).Create(&newAcc).Error; err != nil {
		return nil, err
	}
	return &newAcc, nil
}

func (r *authRepository) FindAccountWithUser(ctx context.Context, accountNo string) (*model.Account, *model.User, error) {
	if r.db == nil {
		return nil, nil, gorm.ErrRecordNotFound
	}
	var account model.Account
	if err := r.db.WithContext(ctx).Preload("User").Where("account_number = ?", accountNo).First(&account).Error; err != nil {
		return nil, nil, err
	}
	return &account, account.User, nil
}

func (r *authRepository) PhoneUsedByOtherUser(ctx context.Context, phone, userID string) (bool, error) {
	if r.db == nil {
		return false, gorm.ErrInvalidDB
	}
	var n int64
	err := r.db.WithContext(ctx).Model(&model.User{}).
		Where("phone_number = ? AND id <> ?", phone, userID).Count(&n).Error
	return n > 0, err
}

// SetActivationCredentials stores credentials after a successful OTP verification
// and binds the verified phone number and device.
func (r *authRepository) SetActivationCredentials(ctx context.Context, userID, passwordHash, pinHash, phoneNumber, deviceID string) error {
	if r.db == nil {
		return gorm.ErrInvalidDB
	}
	updates := map[string]interface{}{
		"password_hash":         passwordHash,
		"pin_hash":              pinHash,
		"device_id":             deviceID,
		"failed_login_attempts": 0,
		"failed_pin_attempts":   0,
		"is_active":             true,
		"updated_at":            time.Now(),
	}
	if phoneNumber != "" && phoneNumber != "0" {
		updates["phone_number"] = phoneNumber
	}
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", userID).Updates(updates).Error
}

func (r *authRepository) UpdatePasswordHash(ctx context.Context, userID, passwordHash, deviceID string) error {
	if r.db == nil {
		return gorm.ErrInvalidDB
	}
	updates := map[string]interface{}{
		"password_hash":         passwordHash,
		"failed_login_attempts": 0,
		"is_active":             true,
		"updated_at":            time.Now(),
	}
	if deviceID != "" {
		updates["device_id"] = deviceID
	}
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", userID).Updates(updates).Error
}

func (r *authRepository) UpdateOnlyPINHash(ctx context.Context, userID, pinHash string) error {
	if r.db == nil {
		return gorm.ErrInvalidDB
	}
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", userID).Updates(map[string]interface{}{
		"pin_hash":            pinHash,
		"failed_pin_attempts": 0,
		"updated_at":          time.Now(),
	}).Error
}

// incrementCounter atomically increments a failure counter and blocks the
// account when the limit is reached (no read-modify-write race, audit DMB-018).
func incrementCounter(ctx context.Context, db *gorm.DB, userID, column string, maxAttempts int) (int, bool, error) {
	if db == nil {
		return 0, false, gorm.ErrInvalidDB
	}
	if maxAttempts <= 0 {
		maxAttempts = 3
	}
	var attempts int
	err := db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&model.User{}).Where("id = ?", userID).
			Updates(map[string]interface{}{column: gorm.Expr(column + " + 1"), "updated_at": time.Now()}).Error; err != nil {
			return err
		}
		if err := tx.Model(&model.User{}).Where("id = ?", userID).Select(column).Scan(&attempts).Error; err != nil {
			return err
		}
		if attempts >= maxAttempts {
			return tx.Model(&model.User{}).Where("id = ?", userID).Update("is_active", false).Error
		}
		return nil
	})
	if err != nil {
		return 0, false, err
	}
	return attempts, attempts >= maxAttempts, nil
}

func (r *authRepository) IncrementFailedLogin(ctx context.Context, userID string, maxAttempts int) (int, bool, error) {
	return incrementCounter(ctx, r.db, userID, "failed_login_attempts", maxAttempts)
}

func (r *authRepository) ResetFailedLogin(ctx context.Context, userID string) error {
	if r.db == nil {
		return gorm.ErrInvalidDB
	}
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", userID).Updates(map[string]interface{}{
		"failed_login_attempts": 0, "updated_at": time.Now(),
	}).Error
}

func (r *authRepository) IncrementFailedPIN(ctx context.Context, userID string, maxAttempts int) (int, bool, error) {
	return incrementCounter(ctx, r.db, userID, "failed_pin_attempts", maxAttempts)
}

func (r *authRepository) ResetFailedPIN(ctx context.Context, userID string) error {
	if r.db == nil {
		return gorm.ErrInvalidDB
	}
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", userID).Updates(map[string]interface{}{
		"failed_pin_attempts": 0, "updated_at": time.Now(),
	}).Error
}

// UpsertCBSUserAndAccount mirrors a CBS customer (looked up strictly by CIF) into the
// local database. New customers are created WITHOUT credentials: login is impossible
// until the activation flow (OTP to the CBS-registered phone) sets password and PIN
// (audit DMB-003). Existing credentials, phone and device bindings are not modified.
func (r *authRepository) UpsertCBSUserAndAccount(ctx context.Context, nasabah *domain.CBSNasabahData, bal *domain.BalanceResponse) (*model.User, *model.Account, error) {
	if r.db == nil {
		return nil, nil, gorm.ErrInvalidDB
	}
	if nasabah == nil || strings.TrimSpace(nasabah.CIF) == "" {
		return nil, nil, errors.New("data nasabah CBS tidak lengkap")
	}
	cif := strings.TrimSpace(nasabah.CIF)

	accountNo, fullName, productCode, accountType := "", nasabah.Nama, "", "Tabungan Mandiri DMB"
	var balance, minBal, blockBal, effBal money.Amount
	if bal != nil {
		accountNo = bal.AccountNumber
		if fullName == "" {
			fullName = bal.HolderName
		}
		productCode = bal.ProductCode
		if bal.AccountType != "" {
			accountType = bal.AccountType
		}
		balance, minBal, blockBal, effBal = bal.Balance, bal.MinimumBalance, bal.BlockedBalance, bal.EffectiveBalance
	}

	fullName = truncateString(strings.TrimSpace(fullName), 100)
	cif = truncateString(strings.TrimSpace(cif), 20)
	accountNo = truncateString(strings.TrimSpace(accountNo), 30)
	productCode = truncateString(strings.TrimSpace(productCode), 20)
	accountType = truncateString(strings.TrimSpace(accountType), 30)
	kodePos := truncateString(strings.TrimSpace(nasabah.KodePos), 15)
	rawJK := strings.ToUpper(strings.TrimSpace(nasabah.JenisKelamin))
	jenisKelamin := truncateString(rawJK, 5)
	if len(rawJK) > 5 {
		if strings.HasPrefix(rawJK, "L") {
			jenisKelamin = "L"
		} else if strings.HasPrefix(rawJK, "P") || strings.HasPrefix(rawJK, "W") {
			jenisKelamin = "P"
		}
	}
	agama := truncateString(strings.TrimSpace(nasabah.Agama), 30)

	var user model.User
	err := r.db.WithContext(ctx).Where("cif = ?", cif).First(&user).Error
	switch {
	case errors.Is(err, gorm.ErrRecordNotFound):
		// The phone column is unique and not null; until activation completes we store a
		// non-routable placeholder derived from the CIF (never a customer-supplied number).
		user = model.User{
			ID:             uuid.NewString(),
			NIK:            crypto.EncryptedString(nasabah.NIK),
			CIF:            cif,
			FullName:       fullName,
			PhoneNumber:    pendingPhonePlaceholder(cif),
			Email:          crypto.EncryptedString(nasabah.Email),
			Alamat:         crypto.EncryptedString(nasabah.Alamat),
			KodePos:        kodePos,
			JenisKelamin:   jenisKelamin,
			Agama:          agama,
			TglLahir:       crypto.EncryptedString(nasabah.TglLahir),
			TempatLahir:    crypto.EncryptedString(nasabah.TempatLahir),
			NamaIbuKandung: crypto.EncryptedString(nasabah.NamaIbuKandung),
			PasswordHash:   "", // not activated
			PINHash:        "", // not activated
			IsActive:       true,
			CreatedAt:      time.Now(),
			UpdatedAt:      time.Now(),
		}
		if err := r.db.WithContext(ctx).Create(&user).Error; err != nil {
			return nil, nil, fmt.Errorf("create user (cif=%s, agama=%q len=%d, jk=%q len=%d, pos=%q len=%d): %w", user.CIF, user.Agama, len(user.Agama), user.JenisKelamin, len(user.JenisKelamin), user.KodePos, len(user.KodePos), err)
		}
	case err != nil:
		return nil, nil, err
	default:
		updates := map[string]interface{}{"updated_at": time.Now()}
		if fullName != "" {
			updates["full_name"] = fullName
		}
		for col, v := range map[string]string{
			"nik": nasabah.NIK, "email": nasabah.Email, "alamat": nasabah.Alamat, "tgl_lahir": nasabah.TglLahir,
			"tempat_lahir": nasabah.TempatLahir, "nama_ibu_kandung": nasabah.NamaIbuKandung,
		} {
			if v == "" {
				continue
			}
			enc, encErr := crypto.EncryptString(v)
			if encErr != nil {
				return nil, nil, encErr
			}
			updates[col] = enc
		}
		if nasabah.KodePos != "" {
			updates["kode_pos"] = kodePos
		}
		if nasabah.JenisKelamin != "" {
			updates["jenis_kelamin"] = jenisKelamin
		}
		if nasabah.Agama != "" {
			updates["agama"] = agama
		}
		if err := r.db.WithContext(ctx).Model(&user).Updates(updates).Error; err != nil {
			return nil, nil, fmt.Errorf("update user (cif=%s): %w", user.CIF, err)
		}
	}

	if accountNo == "" {
		acc, err := r.EnsurePrimaryAccount(ctx, &user, "")
		return &user, acc, err
	}

	// The account comes from CBS for this CIF, which is authoritative for ownership.
	var acc model.Account
	if err := r.db.WithContext(ctx).Where("account_number = ?", accountNo).First(&acc).Error; err != nil {
		acc = model.Account{
			ID: uuid.NewString(), UserID: user.ID, AccountNumber: accountNo, HolderName: fullName,
			ProductCode: productCode, AccountType: accountType, Balance: balance, MinimumBalance: minBal,
			BlockedBalance: blockBal, EffectiveBalance: effBal, Status: model.AccountStatusActive,
			CreatedAt: time.Now(), UpdatedAt: time.Now(),
		}
		if err := r.db.WithContext(ctx).Create(&acc).Error; err != nil {
			return &user, nil, fmt.Errorf("create account (acc=%q len=%d, type=%q len=%d, prod=%q len=%d): %w", acc.AccountNumber, len(acc.AccountNumber), acc.AccountType, len(acc.AccountType), acc.ProductCode, len(acc.ProductCode), err)
		}
	} else {
		if err := r.db.WithContext(ctx).Model(&acc).Updates(map[string]interface{}{
			"user_id": user.ID, "holder_name": fullName, "product_code": productCode, "account_type": accountType,
			"balance": balance, "minimum_balance": minBal, "blocked_balance": blockBal, "effective_balance": effBal,
			"updated_at": time.Now(),
		}).Error; err != nil {
			return &user, nil, fmt.Errorf("update account (acc=%q): %w", acc.AccountNumber, err)
		}
	}
	return &user, &acc, nil
}
