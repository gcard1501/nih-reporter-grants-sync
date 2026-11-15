# Setup notes

## macOS OpenSSL note

*As of November 2026 (mssql-python 1.17.0, bundled ODBC Driver 18.6.2.2, Homebrew openssl@3 3.5.9).*

### Setup on a new Mac

`brew install openssl@3`, then run every Python script through `./run.sh` (for example `./run.sh python test_connection.py`).

### Symptom

Connecting to SQL Server from Python fails with:

```
SSL Provider: [OpenSSL library could not be loaded, make sure OpenSSL 1.0, 1.1, or 3.0 is installed]
```

### Cause

Microsoft's ODBC Driver 18 encrypts the connection with OpenSSL, which it loads at runtime through Homebrew's generic shortcut `/opt/homebrew/opt/openssl`, as `/opt/homebrew/opt/openssl/lib/libssl.dylib`. Homebrew creates that shortcut only for its *default* OpenSSL, which is now version 4. The driver doesn't support version 4, and it never asks for OpenSSL 3 by its versioned file name, so having openssl@3 installed isn't enough:

- If openssl@4 is installed, the shortcut points to it, and the driver rejects it.
- If openssl@4 isn't installed (our case), the shortcut doesn't exist, and the driver finds nothing.

`mssql-python` bundles this same driver (but not OpenSSL), so it hits the same error. We confirmed this by tracing library loads with `DYLD_PRINT_SEARCHING=1`.

### Fix

[`run.sh`](../run.sh) runs one command with `DYLD_LIBRARY_PATH=/opt/homebrew/opt/openssl@3/lib`. That tells the macOS library loader to look in openssl@3's shortcut first, so the driver gets OpenSSL 3.

- **What it changes:** one environment variable, only for the command it starts (and anything that command starts). When the command ends, the setting is gone. Your terminal is unaffected.
- **What it doesn't change:** nothing else on the Mac. No Homebrew shortcuts, no installed packages, no shell profile, no system files.
- **Tested:** the connection succeeds through `run.sh` and fails without it.

### Why this fix

The other option was to repoint Homebrew's `opt/openssl` shortcut to openssl@3. That would affect every program using the shortcut, and Homebrew could quietly undo it on a future `brew upgrade`. `run.sh` is explicit, limited to this project and easy to delete once Microsoft's driver supports OpenSSL 4.

### Homebrew driver not needed

`mssql-python` bundles its own ODBC driver and driver manager. Tracing its loads with `DYLD_PRINT_LIBRARIES=1` showed nothing ODBC-related comes from Homebrew. So `msodbcsql18` and `unixodbc` were uninstalled, and the connection still works through `run.sh`.

### Retest after upgrading mssql-python

A future mssql-python release may bundle a driver that supports OpenSSL 4 or bundle OpenSSL itself. After upgrading, run `python test_connection.py` **without** `run.sh`. If it connects, `run.sh` and this note can be retired.

### Local only

Connections use `Encrypt=yes;TrustServerCertificate=yes`. Traffic is encrypted, but the server's identity isn't verified, because the Docker container uses a self-signed certificate. That's acceptable on your own machine. In production, use a properly issued certificate and `TrustServerCertificate=no`.
