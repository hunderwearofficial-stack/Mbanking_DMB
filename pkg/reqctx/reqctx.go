package reqctx

import "context"

type ctxKey int

const (
	metaKey ctxKey = iota
	adminKey
)

type Meta struct {
	RequestID string
	ClientIP  string
	UserAgent string
}

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
