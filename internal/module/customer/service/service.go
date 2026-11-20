package service

import (
	"context"
	"errors"
	"fmt"
	"mbanking-bpr/pkg/money"
	"strings"

	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/internal/module/customer/repository"
	"mbanking-bpr/internal/notification"
)

var (
	ErrValidation       = errors.New("data tidak valid")
	ErrCustomerNotFound = errors.New("data nasabah tidak ditemukan")
)

type ProductApplicationInput struct {
	ProductType     string       `json:"product_type"`
	ProductName     string       `json:"product_name"`
	Amount          money.Amount `json:"amount"`
	TenorMonths     int          `json:"tenor_months"`
	InterestRate    string       `json:"interest_rate"`
	EstimatedReturn money.Amount `json:"estimated_return"`
	PurposeOrSource string       `json:"purpose_or_source"`
}

type CustomerService interface {
	ListNotifications(ctx context.Context, userID string, limit int) ([]model.Notification, error)
	MarkNotificationsRead(ctx context.Context, userID string) error

	CreateProductApplication(ctx context.Context, userID string, in ProductApplicationInput) (*model.ProductApplication, error)
	ListProductApplications(ctx context.Context, userID string) ([]model.ProductApplication, error)
}

type customerService struct {
	repo repository.CustomerRepository
}

func NewCustomerService(repo repository.CustomerRepository) CustomerService {
	return &customerService{repo: repo}
}

func limitLen(s string, n int) string {
	s = strings.TrimSpace(s)
	if len(s) > n {
		return s[:n]
	}
	return s
}

func (s *customerService) ListNotifications(ctx context.Context, userID string, limit int) ([]model.Notification, error) {
	return s.repo.ListNotifications(ctx, userID, limit)
}

func (s *customerService) MarkNotificationsRead(ctx context.Context, userID string) error {
	return s.repo.MarkNotificationsRead(ctx, userID)
}

func (s *customerService) CreateProductApplication(ctx context.Context, userID string, in ProductApplicationInput) (*model.ProductApplication, error) {
	user, err := s.repo.GetUserByID(ctx, userID)
	if err != nil || user == nil {
		return nil, ErrCustomerNotFound
	}
	ptype := strings.ToUpper(strings.TrimSpace(in.ProductType))
	if ptype == "DEPOSIT" {
		ptype = "DEPOSITO"
	}
	if ptype == "LOAN" || ptype == "KREDIT" {
		ptype = "PINJAMAN"
	}
	if ptype != "DEPOSITO" && ptype != "PINJAMAN" {
		return nil, fmt.Errorf("%w: jenis produk harus DEPOSITO atau PINJAMAN", ErrValidation)
	}
	if in.Amount <= 0 || in.Amount > money.Rupiah(100_000_000_000) || in.TenorMonths <= 0 || in.TenorMonths > 360 {
		return nil, fmt.Errorf("%w: nominal/tenor tidak valid", ErrValidation)
	}
	name := limitLen(in.ProductName, 100)
	if name == "" {
		return nil, fmt.Errorf("%w: nama produk wajib diisi", ErrValidation)
	}
	app := &model.ProductApplication{
		UserID: user.ID, CIF: user.CIF, FullName: user.FullName, PhoneNumber: user.PhoneNumber,
		ProductType: ptype, ProductName: name, Amount: in.Amount, TenorMonths: in.TenorMonths,
		InterestRate: limitLen(in.InterestRate, 50), EstimatedReturn: in.EstimatedReturn,
		PurposeOrSource: limitLen(in.PurposeOrSource, 255),
	}
	if err := s.repo.CreateProductApplication(ctx, app); err != nil {
		return nil, err
	}
	audit.Record(ctx, s.repo.DB(), "NASABAH", user.ID, user.FullName, "SUBMIT_PRODUCT_APPLICATION", app.ProductName, "SUCCESS", user.DeviceID,
		fmt.Sprintf("Pengajuan %s sebesar %s (Tenor %d bulan)", app.ProductName, money.FormatIDR(app.Amount), app.TenorMonths))
	notification.CreateAndPush(ctx, s.repo.DB(), user.ID, "Pengajuan "+app.ProductName+" Diterima",
		fmt.Sprintf("Pengajuan %s sebesar %s (Tenor %d bulan) telah diterima. Petugas Bank DMB akan segera menindaklanjuti.", app.ProductName, money.FormatIDR(app.Amount), app.TenorMonths), notification.CategoryInfo)
	return app, nil
}

func (s *customerService) ListProductApplications(ctx context.Context, userID string) ([]model.ProductApplication, error) {
	return s.repo.ListProductApplications(ctx, userID)
}
