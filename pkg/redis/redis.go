package redis

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/pkg/logger"

	goredis "github.com/redis/go-redis/v9"
)

// ErrNotFound is returned when a key does not exist or has expired.
var ErrNotFound = errors.New("key tidak ditemukan")

// Client wraps Redis with an in-process fallback (single-instance only).
// The fallback keeps controls ENFORCED (rate limits, OTP state) but is not
// shared across instances; production deployments must run Redis.
type Client struct {
	rdb        *goredis.Client
	isFallback bool

	mu  sync.Mutex
	mem map[string]memItem
}

type memItem struct {
	value     []byte
	count     int64
	expiresAt time.Time
}

// InitRedis connects to Redis. An unreachable server is an error (never a silent
// fallback); the caller decides — production refuses to start.
func InitRedis(cfg *config.Config) (*Client, error) {
	addr := fmt.Sprintf("%s:%s", cfg.RedisHost, cfg.RedisPort)
	rdb := goredis.NewClient(&goredis.Options{
		Addr:     addr,
		Password: cfg.RedisPass,
		DB:       cfg.RedisDB,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	if err := rdb.Ping(ctx).Err(); err != nil {
		_ = rdb.Close()
		return nil, fmt.Errorf("redis %s tidak dapat dihubungi: %w", addr, err)
	}

	logger.GetLogger().Info("Redis berhasil terhubung", map[string]interface{}{"addr": addr, "db": cfg.RedisDB})
	return &Client{rdb: rdb, mem: map[string]memItem{}}, nil
}

// NewMemoryClient returns an in-memory client (tests / single-instance fallback).
func NewMemoryClient() *Client {
	return &Client{isFallback: true, mem: map[string]memItem{}}
}

func (c *Client) memGet(key string, now time.Time) (memItem, bool) {
	it, ok := c.mem[key]
	if !ok {
		return memItem{}, false
	}
	if !it.expiresAt.IsZero() && now.After(it.expiresAt) {
		delete(c.mem, key)
		return memItem{}, false
	}
	return it, true
}

// IncrementAndCheckRateLimit increments the hit count for key within a fixed window.
// Returns allowed, remaining, error. Callers must treat an error as "deny" (fail-closed).
func (c *Client) IncrementAndCheckRateLimit(ctx context.Context, key string, limit int, windowSeconds int) (bool, int, error) {
	window := time.Duration(windowSeconds) * time.Second
	count, err := c.IncrWithTTL(ctx, key, window)
	if err != nil {
		return false, 0, err
	}
	if count > int64(limit) {
		return false, 0, nil
	}
	return true, limit - int(count), nil
}

// IncrWithTTL atomically increments a counter; the TTL is set when the key is created.
func (c *Client) IncrWithTTL(ctx context.Context, key string, ttl time.Duration) (int64, error) {
	if !c.isFallback && c.rdb != nil {
		pipe := c.rdb.TxPipeline()
		incr := pipe.Incr(ctx, key)
		pipe.ExpireNX(ctx, key, ttl)
		if _, err := pipe.Exec(ctx); err != nil {
			return 0, err
		}
		return incr.Val(), nil
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	now := time.Now()
	it, ok := c.memGet(key, now)
	if !ok {
		it = memItem{expiresAt: now.Add(ttl)}
	}
	it.count++
	c.mem[key] = it
	return it.count, nil
}

// Set stores a value with TTL.
func (c *Client) Set(ctx context.Context, key string, value []byte, ttl time.Duration) error {
	if !c.isFallback && c.rdb != nil {
		return c.rdb.Set(ctx, key, value, ttl).Err()
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.mem[key] = memItem{value: append([]byte(nil), value...), expiresAt: time.Now().Add(ttl)}
	return nil
}

// Get returns the value for key or ErrNotFound.
func (c *Client) Get(ctx context.Context, key string) ([]byte, error) {
	if !c.isFallback && c.rdb != nil {
		v, err := c.rdb.Get(ctx, key).Bytes()
		if errors.Is(err, goredis.Nil) {
			return nil, ErrNotFound
		}
		return v, err
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	it, ok := c.memGet(key, time.Now())
	if !ok || it.value == nil {
		return nil, ErrNotFound
	}
	return append([]byte(nil), it.value...), nil
}

// TTL returns the remaining lifetime of key (0 if missing).
func (c *Client) TTL(ctx context.Context, key string) time.Duration {
	if !c.isFallback && c.rdb != nil {
		d, err := c.rdb.TTL(ctx, key).Result()
		if err != nil || d < 0 {
			return 0
		}
		return d
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	it, ok := c.memGet(key, time.Now())
	if !ok {
		return 0
	}
	return time.Until(it.expiresAt)
}

// Del deletes keys.
func (c *Client) Del(ctx context.Context, keys ...string) error {
	if !c.isFallback && c.rdb != nil {
		return c.rdb.Del(ctx, keys...).Err()
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	for _, k := range keys {
		delete(c.mem, k)
	}
	return nil
}

// GetClient returns underlying redis client if connected
func (c *Client) GetClient() *goredis.Client {
	return c.rdb
}

// IsFallback returns true if running in-memory
func (c *Client) IsFallback() bool {
	return c.isFallback
}

// Ping checks connectivity (always nil for the in-memory client).
func (c *Client) Ping(ctx context.Context) error {
	if c.isFallback || c.rdb == nil {
		return nil
	}
	return c.rdb.Ping(ctx).Err()
}
