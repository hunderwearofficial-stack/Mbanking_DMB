package crypto

func resetKeysForTest() {
	keyMu.Lock()
	defer keyMu.Unlock()
	activeKey = nil
	previousKey = nil
}
