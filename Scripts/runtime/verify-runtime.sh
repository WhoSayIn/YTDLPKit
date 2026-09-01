#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <runtime-build-directory>" >&2
    exit 64
fi

BUILD_DIR=$1
PYTHON_BIN=${PYTHON_BIN:-python3}

"$PYTHON_BIN" - "$BUILD_DIR" <<'PY'
import hashlib
import json
import plistlib
import subprocess
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1])
dist = root / "dist"
staging = root / "staging"
manifest = json.loads((dist / "ArtifactManifest.json").read_text())
provenance = json.loads((dist / "BuildProvenance.json").read_text())
sbom = json.loads((dist / "SBOM.spdx.json").read_text())
runtime_lock = json.loads((dist / "runtime-lock.json").read_text())

def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

for artifact in manifest["artifacts"]:
    path = dist / artifact["file"]
    assert path.is_file(), path
    assert digest(path) == artifact["sha256"], path
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, path

assert provenance["subject"] == [
    {"name": artifact["file"], "sha256": artifact["sha256"]}
    for artifact in manifest["artifacts"]
]
assert provenance["materials"][0]["sha256"] == manifest["source"]["sha256"]
openssl = next(component for component in runtime_lock["components"] if component["name"] == "OpenSSL")
expat_lock = next(component for component in runtime_lock["components"] if component["name"] == "Expat")
assert {
    "uri": openssl["privacyManifestURL"],
    "sha256": openssl["privacyManifestSHA256"],
} in provenance["materials"]
assert {
    "uri": expat_lock["sourceURL"],
    "sha256": expat_lock["licenseSHA256"],
} in provenance["materials"]
assert sbom["spdxVersion"] == "SPDX-2.3"
assert any(package["name"] == "CPython" for package in sbom["packages"])
expat = next(package for package in sbom["packages"] if package["name"] == "Expat")
assert expat["versionInfo"] == "2.8.1"
assert expat["licenseDeclared"] == "MIT"
assert {
    "spdxElementId": "SPDXRef-Package-1",
    "relationshipType": "DEPENDS_ON",
    "relatedSpdxElement": expat["SPDXID"],
} in sbom["relationships"]
python_resources = {resource["name"]: resource for resource in manifest["pythonResources"]}
assert set(python_resources) == {"certifi", "yt-dlp", "yt-dlp-apple-webkit-jsi"}
assert python_resources["yt-dlp"]["version"] == "2026.08.19"
assert python_resources["certifi"]["version"] == "2026.7.22"
provider_resource = python_resources["yt-dlp-apple-webkit-jsi"]
assert provider_resource["version"] == "0.1.1"
assert provider_resource["sourceCommit"] == "e466daca67cc0e1ca63b68cb8fbe80af16ce00a4"
for resource in python_resources.values():
    expected_material = {"uri": resource["source"], "sha256": resource["sha256"]}
    if "sourceCommit" in resource:
        expected_material["sourceCommit"] = resource["sourceCommit"]
    assert expected_material in provenance["materials"]
    package = next(package for package in sbom["packages"] if package["name"] == resource["name"])
    assert package["versionInfo"] == resource["version"]
    assert package["downloadLocation"] == resource["source"]
    assert package["checksums"] == [{"algorithm": "SHA256", "checksumValue": resource["sha256"]}]
    assert package["licenseDeclared"] == {
        "certifi": "MPL-2.0",
        "yt-dlp": "Unlicense",
        "yt-dlp-apple-webkit-jsi": "Apache-2.0",
    }[resource["name"]]
    assert {
        "spdxElementId": "SPDXRef-Package-YTDLPKitRuntime",
        "relationshipType": "DEPENDS_ON",
        "relatedSpdxElement": package["SPDXID"],
    } in sbom["relationships"]
assert {
    "spdxElementId": "SPDXRef-DOCUMENT",
    "relationshipType": "DESCRIBES",
    "relatedSpdxElement": "SPDXRef-Package-YTDLPKitRuntime",
} in sbom["relationships"]

core = staging / "PythonRuntime.xcframework"
with (core / "Info.plist").open("rb") as stream:
    core_info = plistlib.load(stream)
assert len(core_info["AvailableLibraries"]) == 2
core_device = core / "ios-arm64" / "Python.framework" / "Python"
core_simulator = core / "ios-arm64_x86_64-simulator" / "Python.framework" / "Python"
assert subprocess.check_output(["lipo", "-archs", core_device], text=True).split() == ["arm64"]
assert set(subprocess.check_output(["lipo", "-archs", core_simulator], text=True).split()) == {"arm64", "x86_64"}
expected_core_privacy = {
    "NSPrivacyAccessedAPITypes": [
        {
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp",
            "NSPrivacyAccessedAPITypeReasons": ["C617.1"],
        },
        {
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategorySystemBootTime",
            "NSPrivacyAccessedAPITypeReasons": ["35F9.1"],
        },
    ],
    "NSPrivacyCollectedDataTypes": [],
    "NSPrivacyTracking": False,
    "NSPrivacyTrackingDomains": [],
}
assert manifest["pythonCorePrivacyManifest"]["requiredReasonAPIs"] == {
    "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
    "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
}
for framework in (core_device.parent, core_simulator.parent):
    privacy_path = framework / "PrivacyInfo.xcprivacy"
    assert privacy_path.is_file(), privacy_path
    subprocess.run(["plutil", "-lint", str(privacy_path)], check=True, stdout=subprocess.DEVNULL)
    with privacy_path.open("rb") as stream:
        assert plistlib.load(stream) == expected_core_privacy

extensions = sorted((staging / "Extensions").glob("*.xcframework"))
assert len(extensions) == manifest["extensionCount"]
excluded = set(manifest["excludedExtensionModules"])
expected_excluded = {
    "_ctypes_test", "_testbuffer", "_testcapi", "_testclinic",
    "_testclinic_limited", "_testexternalinspection", "_testimportmultiple",
    "_testinternalcapi", "_testlimitedcapi", "_testmultiphase",
    "_testsinglephase", "_xxtestfuzz", "xxlimited", "xxlimited_35",
    "xxsubtype",
}
assert excluded == expected_excluded
extension_names = {extension.stem for extension in extensions}
assert excluded.isdisjoint(extension_names)
assert {"_hashlib", "_json", "_ssl"}.issubset(extension_names)
expected_privacy = {
    "NSPrivacyAccessedAPITypes": [
        {
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp",
            "NSPrivacyAccessedAPITypeReasons": ["C617.1"],
        }
    ],
    "NSPrivacyCollectedDataTypes": [],
    "NSPrivacyTracking": False,
    "NSPrivacyTrackingDomains": [],
}
for extension in extensions:
    name = extension.stem
    device = extension / "ios-arm64" / f"{name}.framework" / name
    simulator = extension / "ios-arm64_x86_64-simulator" / f"{name}.framework" / name
    device_info = subprocess.check_output(["lipo", "-archs", device], text=True).split()
    simulator_info = subprocess.check_output(["lipo", "-archs", simulator], text=True).split()
    assert device_info == ["arm64"], (name, device_info)
    assert set(simulator_info) == {"arm64", "x86_64"}, (name, simulator_info)
    with (device.parent / "Info.plist").open("rb") as stream:
        assert plistlib.load(stream)["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
    with (simulator.parent / "Info.plist").open("rb") as stream:
        assert plistlib.load(stream)["CFBundleSupportedPlatforms"] == ["iPhoneSimulator"]
    expected_id = f"@rpath/{name}.framework/{name}"
    assert expected_id in subprocess.check_output(["otool", "-D", device], text=True).splitlines()
    assert expected_id in subprocess.check_output(["otool", "-D", simulator], text=True).splitlines()
    for framework in (device.parent, simulator.parent):
        privacy_path = framework / "PrivacyInfo.xcprivacy"
        if name in {"_hashlib", "_ssl"}:
            assert privacy_path.is_file(), privacy_path
            subprocess.run(["plutil", "-lint", str(privacy_path)], check=True, stdout=subprocess.DEVNULL)
            with privacy_path.open("rb") as stream:
                assert plistlib.load(stream) == expected_privacy
        else:
            assert not privacy_path.exists(), privacy_path

if manifest["signing"]["mode"] == "signed":
    frameworks = [core_device.parent, core_simulator.parent]
    frameworks.extend(
        binary.parent
        for extension in extensions
        for binary in (
            extension / "ios-arm64" / f"{extension.stem}.framework" / extension.stem,
            extension / "ios-arm64_x86_64-simulator" / f"{extension.stem}.framework" / extension.stem,
        )
    )
    for framework in frameworks:
        subprocess.run(["codesign", "--verify", "--strict", str(framework)], check=True)
    assert len(frameworks) == 2 + manifest["extensionCount"] * 2
else:
    assert manifest["signing"] == {"mode": "unsigned"}

resources = staging / "PythonRuntimeResources" / "python" / "lib"
expat_license = staging / "PythonRuntimeResources" / "Licenses" / "Expat-COPYING"
assert expat_license.is_file()
assert digest(expat_license) == expat_lock["licenseSHA256"]
stdlib = resources / "python313.zip"
with zipfile.ZipFile(stdlib) as archive:
    names = set(archive.namelist())
    assert "os.py" in names
    assert "ssl.py" in names
    assert not any(name.endswith(".so") for name in names)

expected_sysconfig = {
    "_sysconfigdata__ios_arm64-iphoneos.py",
    "_sysconfigdata__ios_arm64-iphonesimulator.py",
    "_sysconfigdata__ios_x86_64-iphonesimulator.py",
}
assert set(manifest["sysconfigDataFiles"]) == expected_sysconfig
platform_stdlib = resources / "python3.13"
actual_sysconfig = {path.name for path in platform_stdlib.glob("_sysconfigdata__ios_*.py")}
assert actual_sysconfig == expected_sysconfig
for sysconfig_name in expected_sysconfig:
    source = (platform_stdlib / sysconfig_name).read_text()
    assert "build_time_vars" in source, sysconfig_name

placeholders = list((resources / "python3.13" / "lib-dynload").glob("*.fwork"))
# Device uses an iphoneos suffix. Both simulator architectures use the same
# iphonesimulator suffix, so they intentionally share one mapping.
assert len(placeholders) == manifest["extensionCount"] * 2
assert not list(resources.rglob("*.so"))
for placeholder in placeholders:
    name = placeholder.name.split(".", 1)[0]
    assert name not in excluded
    assert placeholder.read_text().strip() == f"Frameworks/{name}.framework/{name}"

print(
    f"Verified Python core, {len(extensions)} extension XCFrameworks, "
    f"{len(placeholders)} loader mappings, and {len(actual_sysconfig)} iOS sysconfig modules"
)
PY
