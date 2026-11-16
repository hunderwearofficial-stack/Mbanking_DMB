// Package reqctx carries verified request metadata (client IP, user agent,
// request id and the authenticated backoffice actor) through context.Context so
// that audit records are attributable (audit DMB-016) without threading extra
// parameters through every service call.
package reqctx

import "context"

type ctxKey int

const (
	metaKey ctxKey = iota
	adminKey
)

// Meta is request metadata captured by middleware.
type Meta struct {
	RequestID string
	ClientIP  string
	UserAgent string
}

// Admin is the authenticated backoffice user.
type Admin struct {
	ID       string
	Username string
	Role     string
}

func WithMeta(ctx context.Context, m Meta) context.Context {
	return context.WithValue(ctx, metaKey, m)
}

func MetaFrom(ctx context.Context) Meta {
	if ctx == nil {
		return Meta{}
	}
	m, _ := ctx.Value(metaKey).(Meta)
	return m
}

func WithAdmin(ctx context.Context, a Admin) context.Context {
	return context.WithValue(ctx, adminKey, a)
}

func AdminFrom(ctx context.Context) (Admin, bool) {
	if ctx == nil {
		return Admin{}, false
	}
	a, ok := ctx.Value(adminKey).(Admin)
	return a, ok && a.ID != ""
}
