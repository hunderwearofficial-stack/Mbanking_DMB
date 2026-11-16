package integration

import (
	"context"

	"mbanking-bpr/internal/app"
	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/legaldoc"
	"mbanking-bpr/internal/legaldoc/pdfdoc"
	"mbanking-bpr/pkg/redis"
)

var (
	itMaker   = legaldoc.Actor{ID: "00000000-0000-0000-0000-00000000a001", Name: "it-maker (COMPLIANCE)"}
	itChecker = legaldoc.Actor{ID: "00000000-0000-0000-0000-00000000a002", Name: "it-checker (SUPER_ADMIN)"}
)

func (e *itEnv) termsService() *legaldoc.Service {
	return legaldoc.NewService(e.db, legaldoc.NewDBFileStore(e.db), pdfdoc.RenderPDF)
}

// publishInitialTerms publishes the migrated version 1 (draft PDF → submit → approve by
// a different officer).
func (e *itEnv) publishInitialTerms() {
	e.t.Helper()
	ctx := context.Background()
	svc := e.termsService()
	vs, err := svc.ListVersions(ctx)
	if err != nil || len(vs) != 1 || vs[0].Status != legaldoc.StatusDraft || vs[0].VersionNumber != 1 {
		e.t.Fatalf("migrasi harus menyediakan SK versi 1 berstatus DRAFT: %v %+v", err, vs)
	}
	id := vs[0].ID
	if _, err := svc.GenerateDraftPDF(ctx, itMaker, id); err != nil {
		e.t.Fatalf("pdf draf: %v", err)
	}
	if _, err := svc.Submit(ctx, itMaker, id, nil); err != nil {
		e.t.Fatalf("submit: %v", err)
	}
	if _, err := svc.Approve(ctx, itChecker, id); err != nil {
		e.t.Fatalf("approve: %v", err)
	}
}

// activeTermsID returns the version id in force (via the public API).
func (e *itEnv) activeTermsID() string {
	e.t.Helper()
	r := e.call("GET", "/api/v1/terms/active", nil, nil)
	if r.Status != 200 {
		e.t.Fatalf("terms/active: %d %v", r.Status, r.Body)
	}
	return r.data()["version_id"].(string)
}

// acceptTerms records the device consent for the version in force and returns its id.
func (e *itEnv) acceptTerms(device string) string {
	e.t.Helper()
	r := e.call("POST", "/api/v1/terms/acceptances", map[string]interface{}{"version_id": e.activeTermsID(), "accepted": true},
		map[string]string{"X-Device-ID": device})
	if r.Status != 201 {
		e.t.Fatalf("terms acceptance: %d %v", r.Status, r.Body)
	}
	return r.data()["acceptance_id"].(string)
}

// freshRateLimits rebuilds the router with an empty in-memory limiter (sessions and
// data stay in PostgreSQL) so that long scenarios are not throttled by design limits.
func (e *itEnv) freshRateLimits() {
	e.t.Helper()
	r, deps, err := app.NewRouter(e.cfg, e.db, redis.NewMemoryClient(), cbsprovider.NewDatabaseCBSProvider(e.db))
	if err != nil {
		e.t.Fatal(err)
	}
	e.router, e.deps = r, deps
}
