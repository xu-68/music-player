"""Check a signed .app identity on macOS without printing certificate/profile data."""
import plistlib
import subprocess
import sys
from pathlib import Path


def validate_identity(bundle_id, signed, profile):
    app_id = signed.get("application-identifier", "")
    prefix, separator, suffix = app_id.partition(".")
    if not separator or suffix != bundle_id or "*" in app_id:
        raise ValueError("Signed application-identifier must be <App ID prefix>.<CFBundleIdentifier>.")
    allowed = profile.get("Entitlements", {}).get("application-identifier", "")
    if allowed.endswith("*"):
        matches = app_id.startswith(allowed[:-1])
    else:
        matches = app_id == allowed
    if not allowed or not matches:
        raise ValueError("Provisioning profile does not authorize the signed application identifier.")
    if prefix not in profile.get("ApplicationIdentifierPrefix", []):
        raise ValueError("App ID prefix does not match the provisioning profile.")
    signed_team = signed.get("com.apple.developer.team-identifier")
    profile_team = profile.get("Entitlements", {}).get("com.apple.developer.team-identifier")
    if not signed_team or signed_team != profile_team:
        raise ValueError("Signing team does not match the provisioning profile.")


def main():
    if len(sys.argv) != 2 or sys.platform != "darwin":
        raise SystemExit("Usage on macOS: python3 ios/scripts/verify_signing.py /path/to/Flamingo.app")
    app = Path(sys.argv[1]).resolve()
    if app.suffix != ".app" or not app.is_dir():
        raise SystemExit("Expected an extracted, signed .app directory.")
    try:
        subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True, capture_output=True)
        signed = plistlib.loads(subprocess.run(
            ["codesign", "-d", "--entitlements", ":-", str(app)],
            check=True, capture_output=True).stdout)
        profile = plistlib.loads(subprocess.run(
            ["security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")],
            check=True, capture_output=True).stdout)
        info = plistlib.loads((app / "Info.plist").read_bytes())
        validate_identity(info["CFBundleIdentifier"], signed, profile)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        # Never dump decoded profiles, entitlements or certificate details.
        message = str(error) if isinstance(error, ValueError) else "Could not verify signature/profile; check the signed app on macOS."
        raise SystemExit(message)
    print("Signature and application identity checks passed.")
    print("This does not verify Dynamic Island behavior; test on the target iPhone.")


if __name__ == "__main__":
    main()
