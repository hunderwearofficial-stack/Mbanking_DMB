package main

import (
	"context"
	"flag"
	"fmt"
	"os"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/rekey"
	"mbanking-bpr/pkg/crypto"
	"mbanking-bpr/pkg/database"
)

func main() {
	apply := flag.Bool("apply", false, "tulis perubahan ke database (default: dry run)")
	batch := flag.Int("batch", 500, "ukuran batch")
	flag.Parse()

	cfg := config.LoadConfig()
	if err := cfg.ValidateDatabase(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if err := crypto.InitKeys(cfg.DBEncryptionKey, cfg.DBEncryptionKeyPrevious); err != nil {
		fmt.Fprintln(os.Stderr, "kunci enkripsi tidak valid:", err)
		os.Exit(1)
	}
	db, err := database.InitPostgres(cfg)
	if err != nil {
		fmt.Fprintln(os.Stderr, "database tidak tersedia:", err)
		os.Exit(1)
	}
	st, err := rekey.Run(context.Background(), db, *apply, *batch)
	fmt.Printf("scanned=%d needs_rekey=%d updated=%d decrypt_errors=%d apply=%t\n",
		st.Scanned, st.NeedsRekey, st.Updated, st.DecryptErrors, *apply)
	if err != nil {
		fmt.Fprintln(os.Stderr, "rekey gagal:", err)
		os.Exit(1)
	}
	if st.DecryptErrors > 0 {
		fmt.Fprintln(os.Stderr, "PERINGATAN: sebagian nilai tidak dapat didekripsi — periksa DB_ENCRYPTION_KEY_PREVIOUS")
		os.Exit(2)
	}
}
