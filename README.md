# Keenans Polymarket Tool 

A powerful, high-fidelity data pipeline and scraping suite designed to harvest, track, and manage Polymarket user profiles, wallet addresses, and leaderboard metrics. 

Equipped with a highly responsive, modern interface, this tool automates the heavy lifting of data collection and curation, allowing users to build actionable databases of Polymarket traders with a single click.

##  Core Features

*    Run Full Tool (End-to-End Pipeline):** Seamlessly executes the entire extraction workflow. It automatically grabs target wallet addresses, updates live tracking metrics, and compiles everything into a localized `accounts.csv` file saved directly to your root directory.
*    Add to Database (Leaderboard Harvester):** Target specific Polymarket leaderboards and extract exact quantities of new profiles to rapidly scale your intelligence database.
*    Download from Database (Data Exporter):** Filter, refine, and extract specific quantities of stored profile datasets from your local database for custom external analysis.
*    Live Metrics Dashboard:** Real-time visual pipeline monitoring featuring instant execution step tracking, database population counters, and clean historical run logging.

## 📁 Architecture & File Outputs

The tool operates on a zero-friction storage methodology:
*   **Automated Output:** No tedious file path configurations required. 
*   **Root Storage:** Running the core pipeline automatically outputs and appends target data directly to `polymarket-tool/accounts.csv` for immediate use in excel, Python scripts, or data models.

Everything work in progress lmao.
