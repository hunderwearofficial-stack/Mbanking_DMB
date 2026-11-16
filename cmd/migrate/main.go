package main

import (
	"context"
	"fmt"
	"os"

	"mbanking-bpr/config"
	"mbanking-bpr/pkg/database"

	"github.com/joho/godotenv"
)

func usage() {
	fmt.Fprintln(os.Stderr, "pemakaian: migrate status | up | grants")
	fmt.Fprintln(os.Stderr, "  wajib: APP_ENV, DB_HOST, DB_NAME, DB_SSL, DB_ENCRYPTION_KEY, MIGRATION_DB_USER, MIGRATION_DB_PASS")
}

func main() {
	if len(os.Args) != 2 {
		usage()
		os.Exit(2)
	}
	cfg := config.LoadConfig()
	owner, ownerPass := os.Getenv("MIGRATION_DB_USER"), os.Getenv("MIGRATION_DB_PASS")
	if owner == "" || ownerPass == "" {
		if envMap, err := godotenv.Read(".env"); err == nil {
			if owner == "" {
				owner = envMap["MIGRATION_DB_USER"]
			}
			if ownerPass == "" {
				ownerPass = envMap["MIGRATION_DB_PASS"]
			}
		}
	}
	if (owner == "" || ownerPass == "") && cfg.AppEnv == "local" {
		owner, ownerPass = cfg.DBUser, cfg.DBPass
	}
	if owner == "" || ownerPass == "" {
		fmt.Fprintln(os.Stderr, "MIGRATION_DB_USER dan MIGRATION_DB_PASS wajib diisi (role pemilik skema, bukan role aplikasi)")
		os.Exit(1)
	}
	cfg.DBUser, cfg.DBPass = owner, ownerPass
	if err := cfg.ValidateDatabase(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	db, err := database.InitPostgres(cfg)
	if err != nil {
		fmt.Fprintln(os.Stderr, "database tidak tersedia:", err)
		os.Exit(1)
	}
	ctx := context.Background()
	switch os.Args[1] {
	case "status":
		st, err := database.MigrationStatusList(ctx, db)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		for _, s := range st {
			state := "PENDING"
			if s.AppliedAt != nil {
				state = "applied " + s.AppliedAt.Format("2006-01-02 15:04:05")
			}
			fmt.Printf("%04d_%-24s %s\n", s.Version, s.Name, state)
		}
	case "up":
		done, err := database.MigrateUp(ctx, db)
		for _, m := range done {
			fmt.Printf("applied %04d_%s\n", m.Version, m.Name)
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, "migrasi gagal:", err)
			os.Exit(1)
		}
		if len(done) == 0 {
			fmt.Println("skema sudah terbaru")
		}
	case "grants":
		if err := database.ApplyRolePrivileges(ctx, db); err != nil {
			fmt.Fprintln(os.Stderr, "grant gagal:", err)
			os.Exit(1)
		}
		fmt.Println("privilege role diterapkan")
	default:
		usage()
		os.Exit(2)
	}
}
