package crypto

// resetKeysForTest clears key material between tests (test-only helper).
func resetKeysForTest() {
	keyMu.Lock()
	defer keyMu.Unlock()
	activeKey = nil
	previousKey = nil
}
