# DP - Advanced Train Job

**Author:** Dzejkop  
**Version:** 1.0.0  
**Framework:** QB, ESX, Qbox (agnostic)

---

## Description

DP - Advanced Train Job is an advanced FiveM script that adds a detailed metro/train driver job. The script is framework-agnostic and supports QB, ESX, and Qbox. It offers a complex system of routes, stations, economy, quests, and progression, all easily configurable.

---

## Main Features

- **Multi-framework support:** QB, ESX, Qbox
- **Fully configurable routes, stations, and timetables**
- **Advanced economy and rewards system**
- **Quest and progression system**
- **NUI interface for players**
- **Easy extension and customization via configs**
- **Optimized for performance and easy integration**

---

## Installation

1. Upload the `dp-advanced-train-job` folder to your `resources` directory.
2. Make sure you have all dependencies installed (`ox_lib`, `oxmysql`, etc.).
3. Add to your `server.cfg`:
   ```
   ensure dp-advanced-train-job
   ```
4. Edit the configuration files in the `config/` folder as needed for your server.

---

## Configuration

All settings can be found in the `config/` directory:
- **config-core.lua** – core script settings
- **config-gameplay.lua** – gameplay mechanics
- **config-progression.lua** – progression system
- **config-economy.lua** – economy and rewards
- **config-metro.lua** – metro and route settings
- **config-train.lua** – train settings
- **config-quests.lua** – quests and tasks
- **config-webhook.lua** – webhooks for logging
- **config-interactions.lua** – player interactions

---

## Files and Folders

- `client/` – client-side logic
- `server/` – server-side logic
- `bridges/` – framework bridges (QB, ESX, Qbox)
- `shared/` – shared utilities, localization
- `UI/` – NUI interface (HTML, JS, CSS)
- `data/` – data for routes, players, etc.
- `sql/` – SQL files for database import

---

## Localization

The script supports multiple languages. Translations can be found in `shared/locales/` (e.g., `en.lua`, `cz.lua`, `de.lua`).

---

## Support & Contact

For support or bug reports, contact the author on Discord or GitHub.

---

## License

This script is for non-commercial use only. Any distribution without the author's consent is prohibited.
