package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"regexp"
	"strings"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/audit"
	"mbanking-bpr/internal/model"
	"mbanking-bpr/pkg/crypto"
	"mbanking-bpr/pkg/database"
	"mbanking-bpr/pkg/money"

	"github.com/google/uuid"
)

var digits = regexp.MustCompile(`^[0-9]+$`)

func fail(msg string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, msg+"\n", args...)
	os.Exit(1)
}

func main() {
	cif := flag.String("cif", "", "CIF uji (12 digit, disarankan awalan 99)")
	phone := flag.String("phone", "", "nomor HP uji (format 08...)")
	account := flag.String("account", "", "nomor rekening tabungan uji (angka)")
	name := flag.String("name", "", "nama nasabah uji")
	balance := flag.Int64("balance", 0, "saldo awal dalam rupiah (bilangan bulat >= 0)")
	flag.Parse()

	cfg := config.LoadConfig()
	if err := cfg.ValidateDatabase(); err != nil {
		fail("%v", err)
	}
	if cfg.AppEnv != config.EnvLocal || !cfg.EnableMockCBS {
		fail("localfixture hanya untuk APP_ENV=local dengan ENABLE_MOCK_CBS=true")
	}
	if n := strings.ToLower(cfg.DBName); !strings.Contains(n, "local") && !strings.Contains(n, "test") {
		fail("menolak: DB_NAME %q tidak mengandung 'local' atau 'test'", cfg.DBName)
	}
	if len(*cif) != 12 || !digits.MatchString(*cif) || !digits.MatchString(*account) || len(*account) < 6 ||
		!strings.HasPrefix(*phone, "08") || !digits.MatchString(*phone) || strings.TrimSpace(*name) == "" || *balance < 0 {
		flag.Usage()
		fail("parameter tidak valid")
	}
	if err := crypto.InitKeys(cfg.DBEncryptionKey, ""); err != nil {
		fail("kunci enkripsi tidak valid: %v", err)
	}
	db, err := database.InitPostgres(cfg)
	if err != nil {
		fail("database tidak tersedia: %v", err)
	}
	ctx := context.Background()
	if err := database.EnsureSchemaCurrent(ctx, db); err != nil {
		fail("%v", err)
	}

	now := time.Now()
	user := model.User{ID: uuid.NewString(), CIF: *cif, FullName: strings.TrimSpace(*name), PhoneNumber: *phone,
		IsActive: true, CreatedAt: now, UpdatedAt: now}
	acc := model.Account{ID: uuid.NewString(), UserID: user.ID, AccountNumber: *account, HolderName: user.FullName,
		AccountType: "TABUNGAN UJI LOKAL", Balance: money.Rupiah(*balance), EffectiveBalance: money.Rupiah(*balance),
		Status: model.AccountStatusActive, CreatedAt: now, UpdatedAt: now}
	if err := db.Create(&user).Error; err != nil {
		fail("gagal membuat nasabah uji (CIF/HP sudah ada?): %v", err)
	}
	if err := db.Create(&acc).Error; err != nil {
		fail("gagal membuat rekening uji (nomor sudah ada?): %v", err)
	}
	audit.Record(ctx, db, "SYSTEM", "localfixture", "local-test-fixture", "LOCAL_TEST_FIXTURE", *account, "SUCCESS", "",
		fmt.Sprintf("Nasabah uji lokal CIF %s dengan saldo awal %s (bukan data nasabah)", *cif, money.FormatIDR(money.Rupiah(*balance))))
	fmt.Printf("Nasabah uji dibuat: CIF %s, HP %s, rekening %s, saldo %s\n", *cif, *phone, *account, money.FormatIDR(money.Rupiah(*balance)))
	fmt.Println("Lanjutkan aktivasi dari aplikasi mobile (menu Aktivasi) — kode OTP tampil di konsol backend.")
}
