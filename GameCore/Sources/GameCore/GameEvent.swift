public enum GameEvent: Equatable {
    case enemySpawned(id: Int)
    case towerFired(towerID: Int, kind: TowerKind, targetID: Int, targetPosition: Vec2)
    case enemyDied(id: Int, kind: EnemyKind, bounty: Int, position: Vec2)
    case enemyLeaked(id: Int, livesLost: Int)
    case waveCompleted(waveNumber: Int, bonus: Int)
    case gameWon
    case gameLost
}

public enum CommandError: Error, Equatable {
    case insufficientGold
    case tileNotBuildable
    case tileOccupied
    case noTowerThere
    case maxLevelReached
    case waveInProgress
    case gameOver
    /// E4 — aktif bir mutatör komutu yasaklıyor: camKuleler yükseltmeyi,
    /// ucKule izin listesi dışındaki kule türünü reddeder.
    case mutatorForbidden
}
