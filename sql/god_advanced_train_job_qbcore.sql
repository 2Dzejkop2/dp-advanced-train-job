-- QB-Core version
-- identifier = citizenid

CREATE TABLE IF NOT EXISTS `god_advanced_train_job_players_train` (
  `identifier` VARCHAR(80) NOT NULL,
  `char_name` VARCHAR(120) NOT NULL,
  `rank` VARCHAR(20) NOT NULL DEFAULT 'trainee',
  `total_km` DOUBLE NOT NULL DEFAULT 0,
  `completed_routes` INT NOT NULL DEFAULT 0,
  `total_stops` INT NOT NULL DEFAULT 0,
  `good_stops` INT NOT NULL DEFAULT 0,
  `xp_total` INT NOT NULL DEFAULT 0,
  `player_level` INT NOT NULL DEFAULT 1,
  `licenses_json` LONGTEXT NULL,
  `quests_json` LONGTEXT NULL,
  `claimed_rewards_json` LONGTEXT NULL,
  `updated_at` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`identifier`),
  KEY `idx_godtrain_train_updated_at` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `god_advanced_train_job_players_metro` (
  `identifier` VARCHAR(80) NOT NULL,
  `char_name` VARCHAR(120) NOT NULL,
  `rank` VARCHAR(20) NOT NULL DEFAULT 'trainee',
  `total_km` DOUBLE NOT NULL DEFAULT 0,
  `completed_routes` INT NOT NULL DEFAULT 0,
  `total_stops` INT NOT NULL DEFAULT 0,
  `good_stops` INT NOT NULL DEFAULT 0,
  `xp_total` INT NOT NULL DEFAULT 0,
  `player_level` INT NOT NULL DEFAULT 1,
  `licenses_json` LONGTEXT NULL,
  `quests_json` LONGTEXT NULL,
  `claimed_rewards_json` LONGTEXT NULL,
  `updated_at` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`identifier`),
  KEY `idx_godtrain_metro_updated_at` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
