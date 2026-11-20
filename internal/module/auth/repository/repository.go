package repository

import (
	"context"
	"errors"
	"fmt"
	"mbanking-bpr/pkg/money"
	"strings"
	"time"

	"mbanking-bpr/internal/devicebind"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/crypto"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

var (
	ErrPhoneInUse          = errors.New("nomor handphone sudah terdaftar pada nasabah lain")
	ErrAccountOwnedByOther = errors.New("rekening terhubung dengan nasabah lain")
)

type AuthRepository interface {
	DB() *gorm.DB
	FindByIdentifier(ctx context.Context, identifier string) (*model.User, error)
	MaxLoginAttempts(ctx context.Context) int
	FindByCIF(ctx context.Context, cif string) (*model.User, error)
	FindByID(ctx context.Context, id string) (*model.User, error)
	FindPrimaryAccount(ctx context.Context, userID string) (*model.Account, error)
	EnsurePrimaryAccount(ctx context.Context, user *model.User, preferredAccountNo string) (*model.Account, error)
	FindAccountWithUser(ctx context.Context, accountNo string) (*model.Account, *model.User, error)
	PhoneUsedByOtherUser(ctx context.Context, phone, userID string) (bool, error)
	IsUsernameTaken(ctx context.Context, username, excludeUserID string) (bool, error)
	SetActivationCredentials(ctx context.Context, userID, username, passwordHash, pinHash, phoneNumber, deviceID string) error
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

// FindByIdentifier resolves a login identifier by its type (audit D-02): a digits-only
// identifier is a phone number or a CIF and never a username; anything else is a username.
// An identifier matching more than one customer is refused instead of picking one.
func (r *authRepository) FindByIdentifier(ctx context.Context, identifier string) (*model.User, error) {
	if r.db == nil || strings.TrimSpace(identifier) == "" {
		return nil, gorm.ErrRecordNotFound
	}
	clean := strings.TrimSpace(identifier)
	q := r.db.WithContext(ctx)
	if isDigits(clean) {
		q = q.Where("phone_number = ? OR cif = ?", clean, clean)
	} else {
		q = q.Where("LOWER(username) = LOWER(?)", clean)
	}
	var users []model.User
	if err := q.Limit(2).Find(&users).Error; err != nil {
		return nil, err
	}
	if len(users) != 1 {
		return nil, gorm.ErrRecordNotFound
	}
	return &users[0], nil
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// MaxLoginAttempts is the backoffice policy (app_configs.max_login_attempts) bounded to
// 3..10; 3 when not configured or unreadable (audit D-07).
func (r *authRepository) MaxLoginAttempts(ctx context.Context) int {
	const def, lo, hi = 3, 3, 10
	if r.db == nil {
		return def
	}
	var n int
	if err := r.db.WithContext(ctx).Raw(`SELECT COALESCE(max_login_attempts, 0) FROM app_configs ORDER BY id LIMIT 1`).Scan(&n).Error; err != nil || n <= 0 {
		return def
	}
	if n < lo {
		return lo
	}
	if n > hi {
		return hi
	}
	return n
}

func (r *authRepository) IsUsernameTaken(ctx context.Context, username, excludeUserID string) (bool, error) {
	if r.db == nil || strings.TrimSpace(username) == "" {
		return false, nil
	}
	var count int64
	q := r.db.WithContext(ctx).Model(&model.User{}).Where("LOWER(username) = LOWER(?)", strings.TrimSpace(username))
	if excludeUserID != "" {
		q = q.Where("id <> ?", excludeUserID)
	}
	if err := q.Count(&count).Error; err != nil {
		return false, err
	}
	return count > 0, nil
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

func pendingPhonePlaceholder(cif string) string {
	p := "P-" + cif
	if len(p) > 20 {
		p = p[:20]
	}
	return p
}

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

func (r *authRepository) SetActivationCredentials(ctx context.Context, userID, username, passwordHash, pinHash, phoneNumber, deviceID string) error {
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
	if strings.TrimSpace(username) != "" {
		updates["username"] = strings.TrimSpace(username)
	}
	if phoneNumber != "" && phoneNumber != "0" {
		updates["phone_number"] = phoneNumber
	}
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&model.User{}).Where("id = ?", userID).Updates(updates).Error; err != nil {
			return err
		}
		return rebindDevice(tx, userID, "ACTIVATION")
	})
}

func rebindDevice(tx *gorm.DB, userID, reason string) error {
	if _, err := devicebind.RevokeUserKeys(tx, userID, reason); err != nil {
		return err
	}
	return devicebind.OpenEnrollmentWindow(tx, userID)
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
	if deviceID == "" {
		return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", userID).Updates(updates).Error
	}
	updates["device_id"] = deviceID
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&model.User{}).Where("id = ?", userID).Updates(updates).Error; err != nil {
			return err
		}
		return rebindDevice(tx, userID, "PASSWORD_RESET_REBIND")
	})
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
	accountNo = truncateString(strings.TrimSpace(accountNo), 100)
	productCode = truncateString(strings.TrimSpace(productCode), 50)
	accountType = truncateString(strings.TrimSpace(accountType), 255)
	kodePos := truncateString(strings.TrimSpace(nasabah.KodePos), 50)
	rawJK := strings.ToUpper(strings.TrimSpace(nasabah.JenisKelamin))
	jenisKelamin := truncateString(rawJK, 50)
	if len(rawJK) > 5 {
		if strings.HasPrefix(rawJK, "L") {
			jenisKelamin = "L"
		} else if strings.HasPrefix(rawJK, "P") || strings.HasPrefix(rawJK, "W") {
			jenisKelamin = "P"
		}
	}
	agama := truncateString(strings.TrimSpace(nasabah.Agama), 255)

	var user model.User
	err := r.db.WithContext(ctx).Where("cif = ?", cif).First(&user).Error
	switch {
	case errors.Is(err, gorm.ErrRecordNotFound):
		user = model.User{
			ID:           uuid.NewString(),
			CIF:          cif,
			FullName:     fullName,
			PhoneNumber:  pendingPhonePlaceholder(cif),
			Email:        crypto.EncryptedString(nasabah.Email),
			KodePos:      kodePos,
			JenisKelamin: jenisKelamin,
			Agama:        agama,
			TglLahir:     crypto.EncryptedString(nasabah.TglLahir),
			TempatLahir:  crypto.EncryptedString(nasabah.TempatLahir),
			PasswordHash: "", // not activated
			PINHash:      "", // not activated
			IsActive:     true,
			CreatedAt:    time.Now(),
			UpdatedAt:    time.Now(),
		}
		if err := r.db.WithContext(ctx).Create(&user).Error; err != nil {
			return nil, nil, fmt.Errorf("create user (agama len=%d, jk len=%d, pos len=%d): %w", len(user.Agama), len(user.JenisKelamin), len(user.KodePos), err)
		}
	case err != nil:
		return nil, nil, err
	default:
		updates := map[string]interface{}{"updated_at": time.Now()}
		if fullName != "" {
			updates["full_name"] = fullName
		}
		for col, v := range map[string]string{
			"email": nasabah.Email, "tgl_lahir": nasabah.TglLahir,
			"tempat_lahir": nasabah.TempatLahir,
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
