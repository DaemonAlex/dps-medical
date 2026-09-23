-- dps-medical tables. Copied from SHOW CREATE TABLE on the live DB, 2026-09-23.
-- The resource does not create these itself; apply once with:
--   mariadb qbox < install/install.sql

CREATE TABLE IF NOT EXISTS `dps_medical_visits` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(50) NOT NULL,
  `event_type` varchar(24) NOT NULL,
  `zone` varchar(16) DEFAULT NULL,
  `injury_type` varchar(16) DEFAULT NULL,
  `condition_key` varchar(48) DEFAULT NULL,
  `item` varchar(48) DEFAULT NULL,
  `staff_citizenid` varchar(50) DEFAULT NULL,
  `staff_name` varchar(80) DEFAULT NULL,
  `staff_job` varchar(48) DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `data` longtext DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_dps_medical_visits_patient` (`citizenid`,`created_at`),
  KEY `idx_dps_medical_visits_type` (`event_type`,`created_at`),
  KEY `idx_dps_medical_visits_staff` (`staff_citizenid`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `dps_medical_conditions` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(50) NOT NULL,
  `condition_key` varchar(48) NOT NULL,
  `severity` tinyint(3) unsigned NOT NULL DEFAULT 1,
  `stage` varchar(24) NOT NULL DEFAULT 'incubating',
  `contagious` tinyint(1) NOT NULL DEFAULT 0,
  `source_citizenid` varchar(50) DEFAULT NULL,
  `source_kind` varchar(24) DEFAULT NULL,
  `contracted_at` datetime NOT NULL DEFAULT current_timestamp(),
  `incubating_until` datetime DEFAULT NULL,
  `diagnosed_at` datetime DEFAULT NULL,
  `diagnosed_by` varchar(50) DEFAULT NULL,
  `treated_at` datetime DEFAULT NULL,
  `resolved_at` datetime DEFAULT NULL,
  `data` longtext DEFAULT NULL,
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_dps_medical_conditions_active` (`citizenid`,`resolved_at`),
  KEY `idx_dps_medical_conditions_key` (`condition_key`,`resolved_at`),
  KEY `idx_dps_medical_conditions_stage` (`stage`,`incubating_until`),
  KEY `idx_dps_medical_conditions_source` (`source_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `dps_medical_immunity` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(50) NOT NULL,
  `condition_key` varchar(48) NOT NULL,
  `reason` varchar(24) NOT NULL DEFAULT 'recovered',
  `granted_at` datetime NOT NULL DEFAULT current_timestamp(),
  `expires_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_dps_medical_immunity` (`citizenid`,`condition_key`),
  KEY `idx_dps_medical_immunity_expiry` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
