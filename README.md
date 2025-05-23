# 📱 ScanSave – QR Code Scanner & Saver

ScanSave is a simple, offline-friendly Flutter app that allows users to scan QR codes and automatically save them locally. It supports scanning various types of QR codes like URLs, text, phone numbers, emails, and Wi-Fi credentials. Scanned data is stored using SQLite and can be searched, exported, or shared.

---

## 🚀 Features

- 🔍 Scan QR codes using the camera
- 📄 View scanned content immediately
- 🕘 Auto-save scanned data to local storage (SQLite)
- 📚 View history of all past scans
- 🗂️ Group scans by type (URL, Text, etc.)
- 🔎 Search within scan history
- 📋 Copy content to clipboard
- 📤 Share scanned content
- 🗑️ Delete individual scan records
- 🌙 Light/Dark mode toggle
- 📁 Export scans to CSV
- 🎯 Custom icons for each scan type
- 🧩 Splash screen and branded app icon
- 🧑‍💻 Built with Flutter and SQLite
- 🌐 100% offline support

---

## 🛠️ Tech Stack

- **Framework:** Flutter
- **QR Scanning:** `mobile_scanner` or `qr_code_scanner`
- **Database:** `sqflite` + `path_provider`
- **State Management:** `Provider`
- **Theme:** Light & Dark Mode with persistence
- **CSV Export:** `csv` package
