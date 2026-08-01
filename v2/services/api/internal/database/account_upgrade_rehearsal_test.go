package database

import "testing"

func TestAccountUpgradeRehearsalPreservesLegacyAccountData(t *testing.T) {
	rehearsal := openAccountUpgradeRehearsal(t)
	rehearsal.seedPreUpgradeData(t)
	rehearsal.assertPreUpgradeData(t)
	rehearsal.applyAccountUpgrade(t)
	rehearsal.assertPostUpgradeData(t)
	rehearsal.rollbackAccountUpgrade(t)
	rehearsal.assertPreUpgradeData(t)
	rehearsal.reapplyAccountUpgrade(t)
	rehearsal.assertPostUpgradeData(t)
}
