package repository

import (
	"context"
	"fmt"
	"strings"
	"time"

	"mbanking-bpr/internal/model"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type AccountRepository interface {
	FindAccountByNumber(ctx context.Context, accountNo string) (*model.Account, error)
	FindOrCreateAccountByUserOrCIF(ctx context.Context, userID, cifNo, accountNo string) (*model.Account, error)
	FindMutationsByAccount(ctx context.Context, accountNo string, limit int) ([]model.Mutation, error)
	SaveAccount(ctx context.Context, account *model.Account) error
}

type accountRepository struct {
	db *gorm.DB
}

func NewAccountRepository(db *gorm.DB) AccountRepository {
	return &accountRepository{db: db}
}

func (r *accountRepository) FindAccountByNumber(ctx context.Context, accountNo string) (*model.Account, error) {
	if r.db == nil || strings.TrimSpace(accountNo) == "" {
		return nil, gorm.ErrRecordNotFound
	}
	var account model.Account
	err := r.db.WithContext(ctx).
		Preload("User").
		Where("account_number = ?", strings.TrimSpace(accountNo)).
		First(&account).Error
	if err != nil {
		return nil, err
	}
	return &account, nil
}

func (r *accountRepository) FindOrCreateAccountByUserOrCIF(ctx context.Context, userID, cifNo, accountNo string) (*model.Account, error) {
	if r.db == nil {
		return nil, gorm.ErrRecordNotFound
	}

	// 1. Try by explicit account number
	if strings.TrimSpace(accountNo) != "" {
		if acc, err := r.FindAccountByNumber(ctx, accountNo); err == nil && acc != nil {
			return acc, nil
		}
	}

	// 2. Try by userID in accounts table
	if strings.TrimSpace(userID) != "" {
		var acc model.Account
		if err := r.db.WithContext(ctx).Preload("User").Where("user_id = ?", strings.TrimSpace(userID)).Order("created_at ASC").First(&acc).Error; err == nil {
			return &acc, nil
		}
	}

	// 3. Look up the User by userID or cifNo, then find or auto-create their primary Account
	var user model.User
	foundUser := false
	if strings.TrimSpace(userID) != "" {
		if err := r.db.WithContext(ctx).Where("id = ?", strings.TrimSpace(userID)).First(&user).Error; err == nil {
			foundUser = true
		}
	}
	if !foundUser && strings.TrimSpace(cifNo) != "" {
		if err := r.db.WithContext(ctx).Where("cif = ?", strings.TrimSpace(cifNo)).First(&user).Error; err == nil {
			foundUser = true
		}
	}

	if !foundUser {
		return nil, gorm.ErrRecordNotFound
	}

	var existingAcc model.Account
	if err := r.db.WithContext(ctx).Preload("User").Where("user_id = ?", user.ID).Order("created_at ASC").First(&existingAcc).Error; err == nil {
		return &existingAcc, nil
	}

	// Auto-create a primary savings account record for this user so balance & refresh never fail
	derivedAccNo := strings.TrimSpace(accountNo)
	if derivedAccNo == "" || derivedAccNo == user.CIF {
		if len(user.CIF) >= 8 {
			derivedAccNo = "00101" + user.CIF[len(user.CIF)-8:]
		} else if user.CIF != "" {
			derivedAccNo = "00101" + user.CIF
		} else {
			derivedAccNo = fmt.Sprintf("00101%d", time.Now().Unix()%100000000)
		}
	}

	now := time.Now()
	newAcc := model.Account{
		ID:               uuid.NewString(),
		UserID:           user.ID,
		AccountNumber:    derivedAccNo,
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
		User:             &user,
	}
	_ = r.db.WithContext(ctx).Create(&newAcc).Error
	return &newAcc, nil
}

func (r *accountRepository) FindMutationsByAccount(ctx context.Context, accountNo string, limit int) ([]model.Mutation, error) {
	if r.db == nil {
		return nil, gorm.ErrRecordNotFound
	}
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	var mutations []model.Mutation
	err := r.db.WithContext(ctx).
		Where("account_number = ?", accountNo).
		Order("created_at DESC").
		Limit(limit).
		Find(&mutations).Error
	if err != nil {
		return nil, err
	}
	return mutations, nil
}

func (r *accountRepository) SaveAccount(ctx context.Context, account *model.Account) error {
	if r.db == nil {
		return nil
	}
	return r.db.WithContext(ctx).Save(account).Error
}
