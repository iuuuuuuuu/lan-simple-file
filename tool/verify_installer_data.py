"""Check that a real client upgrade preserved its SQLite data and preference."""

from pathlib import Path
import sqlite3
import sys


def main():
    database, mode = Path(sys.argv[1]).resolve(), sys.argv[2]
    with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as connection:
        assert connection.execute("PRAGMA integrity_check").fetchone() == ("ok",)
        value = connection.execute(
            "SELECT value FROM settings WHERE key = ?", ("installer.persisted",)
        ).fetchone()
        assert value == ("installer-" + mode,), value
        preference = connection.execute(
            "SELECT value FROM settings WHERE key = ?", ("window.closeAction",)
        ).fetchone()
        assert preference == (("tray",) if mode == "tray" else None), preference
    print("Upgrade data and close preference preserved:", mode)


if __name__ == "__main__":
    main()
