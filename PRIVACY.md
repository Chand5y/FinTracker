
# Privacy Policy for FinTrax

**Last Updated:** October 2026

**FinTrax** ("we", "our", or "the Application") is developed by Chandan Kumar as a privacy-first, offline personal finance tracker.

## 1. Data Collection and Offline Storage
FinTrax operates **100% offline on your device**. All financial records, books, categories, and transaction notes are stored locally in an SQLite database on your smartphone. We do not operate any external servers, and we do not collect, transmit, track, or sell any personal or financial data.

## 2. SMS Permission Usage (`READ_SMS` / `RECEIVE_SMS`)
If you opt in to Smart SMS Auto-Track, FinTrax scans incoming bank and UPI transaction alerts locally on your device to pre-fill expense amounts and merchant names.
* **Strictly Local Processing:** SMS parsing happens entirely on your device. Your SMS messages never leave your phone.
* **OTPs & Personal Texts Ignored:** Personal messages and OTP codes are completely ignored.

## 3. Google Drive API Usage (`drive.appdata` Scope)
If you choose to enable Cloud Backup, FinTrax requests access to your Google Account using the restricted `https://www.googleapis.com/auth/drive.appdata` scope.
* **How We Use Google User Data:** FinTrax uses this permission solely to create, upload, and restore a single encrypted backup file (`fintrax_cloud_backup.json`) inside your personal Google Drive's hidden Application Data folder.
* **No Access to Personal Files:** FinTrax cannot view, access, modify, or delete any of your personal files, photos, or documents on Google Drive.
* **Data Sharing:** We do not share, transfer, or disclose your Google user data to any third parties, advertising networks, or AI models.

## 4. User Control & Data Deletion
You can disconnect your Google Account or delete your local data at any time from within the FinTrax Settings menu, or revoke FinTrax's access and delete its hidden application data directly from your Google Drive Settings (`Settings > Manage Apps > FinTrax`).

## 5. Contact Us
If you have any questions about this Privacy Policy, please contact:
* **Developer:** Chandan Kumar
* **Email:** mkchandankr@gmail.com
* **GitHub:** https://github.com/Chand5y/FinTrax
