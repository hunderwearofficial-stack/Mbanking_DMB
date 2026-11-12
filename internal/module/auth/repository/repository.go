package repository

import (
	"context"
	"fmt"
	"time"

	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/crypto"
	"mbanking-bpr/pkg/utils"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type AuthRepository interface {
	DB() *gorm.DB
	FindByIdentifier(ctx context.Context, identifier string) (*model.User, error)
	FindByID(ctx context.Context, id string) (*model.User, error)
	FindPrimaryAccount(ctx context.Context, userID string) (*model.Account, error)
	EnsurePrimaryAccount(ctx context.Context, user *model.User, preferredAccountNo string) (*model.Account, error)
	FindAccountWithUser(ctx context.Context, accountNo string) (*model.Account, *model.User, error)
	UpdateUserCredentials(ctx context.Context, userID, passwordHash, pinHash, phoneNumber, deviceID string) error
	UpdatePasswordHash(ctx context.Context, userID, passwordHash, deviceID string) error
	UpdateOnlyPINHash(ctx context.Context, userID, pinHash string) error
	IncrementFailedLogin(ctx context.Context, userID string, maxAttempts int) (int, bool, error)
	ResetFailedLogin(ctx context.Context, userID string) error
	UpdateDeviceID(ctx context.Context, userID, deviceID string) error
	CreateUser(ctx context.Context, user *model.User) error
	UpsertCBSUserAndAccount(ctx context.Context, nasabah *domain.CBSNasabahData, bal *domain.BalanceResponse, phone string) (*model.User, *model.Account, error)
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

func (r *authRepository) FindByIdentifier(ctx context.Context, identifier string) (*model.User, error) {
	if r.db == nil {
		return nil, gorm.ErrRecordNotFound
	}
	var user model.User
	// Match either phone_number or cif
	err := r.db.WithContext(ctx).
		Where("phone_number = ? OR cif = ?", identifier, identifier).
		First(&user).Error
	if err != nil {
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

func deriveAccountNoFromCIF(cif string) string {
	if len(cif) >= 8 {
		return "00101" + cif[len(cif)-8:]
	}
	if cif != "" {
		return "00101" + cif
	}
	return fmt.Sprintf("00101%d", time.Now().Unix()%100000000)
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
		_ = r.db.WithContext(ctx).Model(&acc).Updates(map[string]interface{}{
			"user_id":     user.ID,
			"holder_name": user.FullName,
			"status":      model.AccountStatusActive,
			"updated_at":  time.Now(),
		}).Error
		return &acc, nil
	}
	now := time.Now()
	newAcc := model.Account{
		ID:               uuid.NewString(),
		UserID:           user.ID,
		AccountNumber:    accNo,
		HolderName:       user.FullName,
		ProductCode:      "01",
		AccountType:      "Tabungan Mandiri DMB",
		Balance:          0,
		MinimumBalance:   0,
		BlockedBalance:   0,
		EffectiveBalance: 0,
		Status:           model.AccountStatusActive,
		CreatedAt:        now,
		UpdatedAt:        now,
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

func (r *authRepository) UpdateUserCredentials(ctx context.Context, userID, passwordHash, pinHash, phoneNumber, deviceID string) error {
	if r.db == nil {
		return nil
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
		return nil
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
		return nil
	}
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", userID).Updates(map[string]interface{}{
		"pin_hash":            pinHash,
		"failed_pin_attempts": 0,
		"updated_at":          time.Now(),
	}).Error
}

func (r *authRepository) IncrementFailedLogin(ctx context.Context, userID string, maxAttempts int) (int, bool, error) {
	if r.db == nil {
		return 1, false, nil
	}
	if maxAttempts <= 0 {
		maxAttempts = 3
	}
	var user model.User
	if err := r.db.WithContext(ctx).Where("id = ?", userID).First(&user).Error; err != nil {
		return 1, false, err
	}
	attempts := user.FailedLoginAttempts + 1
	blocked := attempts >= maxAttempts
	updates := map[string]interface{}{
		"failed_login_attempts": attempts,
		"updated_at":            time.Now(),
	}
	if blocked {
		updates["is_active"] = false
	}
	_ = r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", userID).Updates(updates).Error
	return attempts, blocked, nil
}

func (r *authRepository) ResetFailedLogin(ctx context.Context, userID string) error {
	if r.db == nil {
		return nil
	}
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", userID).Updates(map[string]interface{}{
		"failed_login_attempts": 0,
		"updated_at":            time.Now(),
	}).Error
}

func (r *authRepository) UpdateDeviceID(ctx context.Context, userID, deviceID string) error {
	if r.db == nil {
		return nil
	}
	return r.db.WithContext(ctx).
		Model(&model.User{}).
		Where("id = ?", userID).
		Update("device_id", deviceID).Error
}

func (r *authRepository) CreateUser(ctx context.Context, user *model.User) error {
	if r.db == nil {
		return nil
	}
	return r.db.WithContext(ctx).Create(user).Error
}

func (r *authRepository) UpsertCBSUserAndAccount(ctx context.Context, nasabah *domain.CBSNasabahData, bal *domain.BalanceResponse, phone string) (*model.User, *model.Account, error) {
	if r.db == nil {
		return nil, nil, gorm.ErrInvalidDB
	}

	accountNo := ""
	fullName := ""
	productCode := ""
	accountType := "Tabungan Mandiri DMB"
	balance := 0.0
	minBal := 0.0
	blockBal := 0.0
	effBal := 0.0

	if bal != nil {
		accountNo = bal.AccountNumber
		fullName = bal.HolderName
		productCode = bal.ProductCode
		if bal.AccountType != "" {
			accountType = bal.AccountType
		}
		balance = bal.Balance
		minBal = bal.MinimumBalance
		blockBal = bal.BlockedBalance
		effBal = bal.EffectiveBalance
	}

	cif := ""
	nik := ""
	email := ""
	alamat := ""
	kodePos := ""
	jenisKelamin := ""
	agama := ""
	tglLahir := ""
	tempatLahir := ""
	namaIbuKandung := ""

	if nasabah != nil {
		cif = nasabah.CIF
		nik = nasabah.NIK
		if nasabah.Nama != "" {
			fullName = nasabah.Nama
		}
		if nasabah.NoHP != "" && nasabah.NoHP != "0" && phone == "" {
			phone = nasabah.NoHP
		}
		email = nasabah.Email
		alamat = nasabah.Alamat
		kodePos = nasabah.KodePos
		jenisKelamin = nasabah.JenisKelamin
		agama = nasabah.Agama
		tglLahir = nasabah.TglLahir
		tempatLahir = nasabah.TempatLahir
		namaIbuKandung = nasabah.NamaIbuKandung
	}

	if cif == "" {
		if len(accountNo) >= 9 {
			cif = "001" + accountNo[len(accountNo)-9:]
		} else {
			cif = fmt.Sprintf("CBS-%s", accountNo)
		}
	}

	defaultPw, _ := utils.HashPassword("rahasia123")
	defaultPin, _ := utils.HashPIN("123456")

	// Check if user with this CIF or phone already exists
	var user model.User
	err := r.db.WithContext(ctx).Where("cif = ? OR phone_number = ?", cif, phone).First(&user).Error
	if err != nil {
		user = model.User{
			ID:             uuid.NewString(),
			NIK:            crypto.EncryptedString(nik),
			CIF:            cif,
			FullName:       fullName,
			PhoneNumber:    phone,
			Email:          crypto.EncryptedString(email),
			Alamat:         crypto.EncryptedString(alamat),
			KodePos:        kodePos,
			JenisKelamin:   jenisKelamin,
			Agama:          agama,
			TglLahir:       crypto.EncryptedString(tglLahir),
			TempatLahir:    crypto.EncryptedString(tempatLahir),
			NamaIbuKandung: crypto.EncryptedString(namaIbuKandung),
			PasswordHash:   defaultPw,
			PINHash:        defaultPin,
			IsActive:       true,
			CreatedAt:      time.Now(),
			UpdatedAt:      time.Now(),
		}
		if createErr := r.db.WithContext(ctx).Create(&user).Error; createErr != nil {
			return nil, nil, createErr
		}
	} else {
		updates := map[string]interface{}{
			"updated_at": time.Now(),
		}
		if fullName != "" {
			updates["full_name"] = fullName
		}
		if nik != "" {
			encNIK, _ := crypto.EncryptString(nik)
			updates["nik"] = encNIK
		}
		if email != "" {
			encEmail, _ := crypto.EncryptString(email)
			updates["email"] = encEmail
		}
		if alamat != "" {
			encAlamat, _ := crypto.EncryptString(alamat)
			updates["alamat"] = encAlamat
		}
		if kodePos != "" {
			updates["kode_pos"] = kodePos
		}
		if jenisKelamin != "" {
			updates["jenis_kelamin"] = jenisKelamin
		}
		if agama != "" {
			updates["agama"] = agama
		}
		if tglLahir != "" {
			encTgl, _ := crypto.EncryptString(tglLahir)
			updates["tgl_lahir"] = encTgl
		}
		if tempatLahir != "" {
			encTempat, _ := crypto.EncryptString(tempatLahir)
			updates["tempat_lahir"] = encTempat
		}
		if namaIbuKandung != "" {
			encIbu, _ := crypto.EncryptString(namaIbuKandung)
			updates["nama_ibu_kandung"] = encIbu
		}
		_ = r.db.WithContext(ctx).Model(&user).Updates(updates).Error
	}

	if accountNo == "" {
		if existing, findErr := r.FindPrimaryAccount(ctx, user.ID); findErr == nil && existing != nil {
			return &user, existing, nil
		}
		accountNo = deriveAccountNoFromCIF(user.CIF)
	}

	var acc model.Account
	if err := r.db.WithContext(ctx).Where("account_number = ?", accountNo).First(&acc).Error; err != nil {
		acc = model.Account{
			ID:               uuid.NewString(),
			UserID:           user.ID,
			AccountNumber:    accountNo,
			HolderName:       fullName,
			ProductCode:      productCode,
			AccountType:      accountType,
			Balance:          balance,
			MinimumBalance:   minBal,
			BlockedBalance:   blockBal,
			EffectiveBalance: effBal,
			Status:           model.AccountStatusActive,
			CreatedAt:        time.Now(),
			UpdatedAt:        time.Now(),
		}
		if createAccErr := r.db.WithContext(ctx).Create(&acc).Error; createAccErr != nil {
			return &user, nil, createAccErr
		}
	} else {
		_ = r.db.WithContext(ctx).Model(&acc).Updates(map[string]interface{}{
			"user_id":           user.ID,
			"holder_name":       fullName,
			"product_code":      productCode,
			"account_type":      accountType,
			"balance":           balance,
			"minimum_balance":   minBal,
			"blocked_balance":   blockBal,
			"effective_balance": effBal,
			"updated_at":        time.Now(),
		}).Error
	}

	return &user, &acc, nil
}
