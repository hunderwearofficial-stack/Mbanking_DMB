package redis

import (
	"context"
	"fmt"
	"sync"
	"time"

	"mbanking-bpr/config"
	"mbanking-bpr/pkg/logger"

	goredis "github.com/redis/go-redis/v9"
)

type Client struct {
	rdb        *goredis.Client
	isFallback bool
	memStore   sync.Map // fallback in-memory store for rate limiting/caching
}

func InitRedis(cfg *config.Config) *Client {
	addr := fmt.Sprintf("%s:%s", cfg.RedisHost, cfg.RedisPort)
	rdb := goredis.NewClient(&goredis.Options{
		Addr:     addr,
		Password: cfg.RedisPass,
		DB:       cfg.RedisDB,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	if err := rdb.Ping(ctx).Err(); err != nil {
		logger.GetLogger().Warn("Redis server tidak terhubung, mengaktifkan Fallback In-Memory Cache/RateLimiter", map[string]interface{}{
			"addr":  addr,
			"error": err.Error(),
		})
		return &Client{
			rdb:        nil,
			isFallback: true,
		}
	}

	logger.GetLogger().Info("Redis berhasil terhubung", map[string]interface{}{
		"addr": addr,
		"db":   cfg.RedisDB,
	})

	return &Client{
		rdb:        rdb,
		isFallback: false,
	}
}

type memoryEntry struct {
	count     int
	expiresAt time.Time
}

// IncrementAndCheckRateLimit increments hit count and checks if within limit
// key: e.g. "ratelimit:login:127.0.0.1"
// limit: max allowed requests
// window: timeframe window in seconds
// Returns: allowed (bool), remaining (int), err (error)
func (c *Client) IncrementAndCheckRateLimit(ctx context.Context, key string, limit int, windowSeconds int) (bool, int, error) {
	windowDuration := time.Duration(windowSeconds) * time.Second

	// Redis path
	if !c.isFallback && c.rdb != nil {
		pipe := c.rdb.TxPipeline()
		incrCmd := pipe.Incr(ctx, key)
		pipe.Expire(ctx, key, windowDuration)
		_, err := pipe.Exec(ctx)
		if err != nil {
			// Fallback on redis error
			return c.fallbackRateLimit(key, limit, windowDuration)
		}

		count := int(incrCmd.Val())
		if count > limit {
			return false, 0, nil
		}
		return true, limit - count, nil
	}

	// In-memory fallback
	return c.fallbackRateLimit(key, limit, windowDuration)
}

func (c *Client) fallbackRateLimit(key string, limit int, window time.Duration) (bool, int, error) {
	now := time.Now()
	val, exists := c.memStore.Load(key)

	var entry *memoryEntry
	if !exists {
		entry = &memoryEntry{
			count:     1,
			expiresAt: now.Add(window),
		}
		c.memStore.Store(key, entry)
		return true, limit - 1, nil
	}

	entry = val.(*memoryEntry)
	if now.After(entry.expiresAt) {
		// Reset window
		entry.count = 1
		entry.expiresAt = now.Add(window)
		c.memStore.Store(key, entry)
		return true, limit - 1, nil
	}

	entry.count++
	c.memStore.Store(key, entry)

	if entry.count > limit {
		return false, 0, nil
	}

	return true, limit - entry.count, nil
}

// GetClient returns underlying redis client if connected
func (c *Client) GetClient() *goredis.Client {
	return c.rdb
}

// IsFallback returns true if running in-memory
func (c *Client) IsFallback() bool {
	return c.isFallback
}

