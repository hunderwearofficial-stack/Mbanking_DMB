package main

import (
	"context"
	"fmt"
	"os"

	"mbanking-bpr/config"
	"mbanking-bpr/internal/audit"
	"mbanking-bpr/pkg/database"
)

func main() {
	cfg := config.LoadConfig()
	if err := cfg.ValidateDatabase(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	db, err := database.InitPostgres(cfg)
	if err != nil {
		fmt.Fprintln(os.Stderr, "database tidak tersedia:", err)
		os.Exit(1)
	}
	seq, err := audit.VerifyChain(context.Background(), db)
	if err != nil {
		if seq > 0 {
			fmt.Fprintf(os.Stderr, "AUDIT CHAIN TIDAK VALID pada seq=%d: %v\n", seq, err)
			os.Exit(2)
		}
		fmt.Fprintln(os.Stderr, "verifikasi gagal:", err)
		os.Exit(1)
	}
	fmt.Println("audit chain utuh")
}
