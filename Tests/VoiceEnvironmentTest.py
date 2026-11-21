"""Exercise the actual configuration executable against an isolated filesystem."""
import json
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

executable = str(Path(sys.argv[1]).resolve())


def invoke(root, operation, succeeds=True):
    result = subprocess.run(
        [executable, operation, "--test-root", str(root)], capture_output=True, text=True
    )
    assert (result.returncode == 0) == succeeds, result.stderr
    return json.loads(result.stdout) if succeeds else result.stderr


with tempfile.TemporaryDirectory(prefix="Rimo-environment-test-") as temporary:
    root = Path(temporary)
    preferences = root / "Library/Preferences/com.apple.MobileBluetooth.debug.plist"
    backup = root / "Library/Application Support/Rimo/VoiceEnvironment/original.plist"
    preferences.parent.mkdir(parents=True)
    original = {"OtherSetting": "keep", "HCITraces": {"HCILiveTraces": False, "Existing": 42}}
    preferences.write_bytes(plistlib.dumps(original))
    assert invoke(root, "status") == {"configured": False, "canRestore": False}
    assert invoke(root, "configure")["configured"]
    first_backup = backup.read_bytes()
    assert invoke(root, "configure")["configured"]
    assert backup.read_bytes() == first_backup, "Repeated configure changed the original backup"
    configured = plistlib.loads(preferences.read_bytes())
    assert configured["OtherSetting"] == "keep"
    assert configured["HCITraces"]["Existing"] == 42
    assert configured["HCITraces"]["HCIFileTraces"] is False
    # Simulate another program modifying an unrelated key while Rimo is configured.
    configured["HCITraces"]["NewSetting"] = 7
    preferences.write_bytes(plistlib.dumps(configured))
    invoke(root, "restore")
    expected = original.copy()
    expected["HCITraces"] = {**original["HCITraces"], "NewSetting": 7}
    assert plistlib.loads(preferences.read_bytes()) == expected
    assert not backup.exists()
    # An originally absent dictionary is removed on restore.
    preferences.write_bytes(plistlib.dumps({"OtherSetting": "keep"}))
    invoke(root, "configure")
    invoke(root, "restore")
    assert plistlib.loads(preferences.read_bytes()) == {"OtherSetting": "keep"}
    # Conflicting writes retain the backup and leave the external value alone.
    invoke(root, "configure")
    configured = plistlib.loads(preferences.read_bytes())
    configured["HCITraces"]["RawAudioTrace"] = "external"
    preferences.write_bytes(plistlib.dumps(configured))
    before = preferences.read_bytes()
    invoke(root, "restore", succeeds=False)
    assert preferences.read_bytes() == before and backup.exists()
    invoke(root, "configure", succeeds=False)
    assert preferences.read_bytes() == before
    # A malformed file is reported without rewriting it.
    preferences.write_bytes(b"broken plist")
    invoke(root, "configure", succeeds=False)
    assert preferences.read_bytes() == b"broken plist"
print("PASS: actual environment tool; configure; readback; idempotence; restore; absent keys; unrelated changes; conflict preservation; malformed file")
