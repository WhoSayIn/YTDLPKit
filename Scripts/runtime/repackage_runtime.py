#!/usr/bin/env python3
"""Repackage BeeWare's iOS support archive into SwiftPM-ready artifacts.

The upstream archive requires an app build phase to move extension modules into
frameworks. This tool performs that transformation once, during release
production. Consumers receive ordinary XCFrameworks and package resources.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

FIXED_ZIP_TIME = (2020, 1, 1, 0, 0, 0)
DEVICE_SLICE = "ios-arm64"
SIMULATOR_SLICE = "ios-arm64_x86_64-simulator"
PRIVACY_MANIFEST_MODULES = frozenset({"_hashlib", "_ssl"})
EXCLUDED_EXTENSION_MODULES = (
    "_ctypes_test",
    "_testbuffer",
    "_testcapi",
    "_testclinic",
    "_testclinic_limited",
    "_testexternalinspection",
    "_testimportmultiple",
    "_testinternalcapi",
    "_testlimitedcapi",
    "_testmultiphase",
    "_testsinglephase",
    "_xxtestfuzz",
    "xxlimited",
    "xxlimited_35",
    "xxsubtype",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_extract(archive: Path, destination: Path) -> None:
    with tarfile.open(archive, "r:gz") as source:
        root = destination.resolve()
        for member in source.getmembers():
            target = (destination / member.name).resolve()
            if root != target and root not in target.parents:
                raise ValueError(f"unsafe archive member: {member.name}")
            if member.issym() or member.islnk():
                link = PurePosixPath(member.linkname)
                if link.is_absolute():
                    raise ValueError(f"unsafe archive link: {member.name}")
                link_target = (target.parent / Path(*link.parts)).resolve()
                if root != link_target and root not in link_target.parents:
                    raise ValueError(f"unsafe archive link: {member.name}")
        source.extractall(destination, filter="data")


def copy_framework(source: Path, destination: Path) -> None:
    shutil.copytree(source, destination, symlinks=True)


def write_plist(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        plistlib.dump(value, stream, fmt=plistlib.FMT_XML, sort_keys=True)


def xcframework_plist(framework_name: str) -> dict:
    return {
        "AvailableLibraries": [
            {
                "BinaryPath": f"{framework_name}.framework/{framework_name}",
                "LibraryIdentifier": DEVICE_SLICE,
                "LibraryPath": f"{framework_name}.framework",
                "SupportedArchitectures": ["arm64"],
                "SupportedPlatform": "ios",
            },
            {
                "BinaryPath": f"{framework_name}.framework/{framework_name}",
                "LibraryIdentifier": SIMULATOR_SLICE,
                "LibraryPath": f"{framework_name}.framework",
                "SupportedArchitectures": ["arm64", "x86_64"],
                "SupportedPlatform": "ios",
                "SupportedPlatformVariant": "simulator",
            },
        ],
        "CFBundlePackageType": "XFWK",
        "XCFrameworkFormatVersion": "1.0",
    }


def framework_plist(module: str) -> dict:
    safe_identifier = module.replace("_", "-")
    return {
        "BuildMachineOSBuild": "",
        "CFBundleDevelopmentRegion": "en",
        "CFBundleExecutable": module,
        "CFBundleIdentifier": f"org.ytdlpkit.python.{safe_identifier}",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": module,
        "CFBundlePackageType": "FMWK",
        "CFBundleShortVersionString": "1.0",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "CFBundleVersion": "1",
        "MinimumOSVersion": "13.0",
    }


def openssl_privacy_manifest() -> dict:
    return {
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


def python_core_privacy_manifest() -> dict:
    return {
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


def run(*command: str) -> None:
    subprocess.run(command, check=True)


def module_name(path: Path) -> str:
    return path.name.split(".", 1)[0]


def indexed_modules(path: Path) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for item in sorted(path.glob("*.so")):
        name = module_name(item)
        if name in result:
            raise ValueError(f"duplicate extension module {name} in {path}")
        result[name] = item
    return result


def create_extension_xcframework(
    name: str,
    device_binary: Path,
    simulator_arm64: Path,
    simulator_x86_64: Path,
    output: Path,
) -> None:
    write_plist(output / "Info.plist", xcframework_plist(name))
    for slice_name in (DEVICE_SLICE, SIMULATOR_SLICE):
        framework = output / slice_name / f"{name}.framework"
        framework.mkdir(parents=True)
        info = framework_plist(name)
        if slice_name == SIMULATOR_SLICE:
            info["CFBundleSupportedPlatforms"] = ["iPhoneSimulator"]
        write_plist(framework / "Info.plist", info)
        if name in PRIVACY_MANIFEST_MODULES:
            write_plist(framework / "PrivacyInfo.xcprivacy", openssl_privacy_manifest())

    device_output = output / DEVICE_SLICE / f"{name}.framework" / name
    simulator_output = output / SIMULATOR_SLICE / f"{name}.framework" / name
    shutil.copy2(device_binary, device_output)
    run("lipo", "-create", str(simulator_arm64), str(simulator_x86_64), "-output", str(simulator_output))
    run("install_name_tool", "-id", f"@rpath/{name}.framework/{name}", str(device_output))
    run("install_name_tool", "-id", f"@rpath/{name}.framework/{name}", str(simulator_output))


def add_zip_entry(archive: zipfile.ZipFile, path: Path, relative: Path) -> None:
    name = relative.as_posix() + ("/" if path.is_dir() else "")
    info = zipfile.ZipInfo(name, FIXED_ZIP_TIME)
    info.create_system = 3
    if path.is_symlink():
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        archive.writestr(info, os.readlink(path).encode())
    elif path.is_dir():
        info.external_attr = (stat.S_IFDIR | 0o755) << 16
        archive.writestr(info, b"")
    else:
        mode = 0o755 if os.access(path, os.X_OK) else 0o644
        info.external_attr = (stat.S_IFREG | mode) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def deterministic_zip(source: Path, output: Path, keep_parent: bool = True) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".partial")
    temporary.unlink(missing_ok=True)
    root = source.parent if keep_parent else source
    entries = [source] + sorted(source.rglob("*"), key=lambda item: item.relative_to(root).as_posix())
    with zipfile.ZipFile(temporary, "w", allowZip64=True) as archive:
        for entry in entries:
            add_zip_entry(archive, entry, entry.relative_to(root))
    temporary.replace(output)


def build_stdlib(
    source: Path,
    resource_root: Path,
    module_paths: list[Path],
    sysconfig_paths: list[Path],
) -> list[str]:
    python_root = resource_root / "python" / "lib"
    python_root.mkdir(parents=True)
    stdlib_zip = python_root / "python313.zip"

    with zipfile.ZipFile(stdlib_zip, "w", allowZip64=True) as archive:
        for item in sorted(source.rglob("*"), key=lambda path: path.relative_to(source).as_posix()):
            if item.is_dir() or item.is_symlink() or "lib-dynload" in item.parts or "__pycache__" in item.parts:
                continue
            relative = item.relative_to(source)
            add_zip_entry(archive, item, relative)

    platform_stdlib = python_root / "python3.13"
    platform_stdlib.mkdir(parents=True)
    sysconfig_names: list[str] = []
    for sysconfig_path in sorted(sysconfig_paths, key=lambda path: path.name):
        if not sysconfig_path.is_file() or not sysconfig_path.name.startswith("_sysconfigdata__ios_"):
            raise ValueError(f"invalid iOS sysconfig module: {sysconfig_path}")
        destination = platform_stdlib / sysconfig_path.name
        if destination.exists():
            raise ValueError(f"duplicate iOS sysconfig module: {sysconfig_path.name}")
        shutil.copy2(sysconfig_path, destination)
        sysconfig_names.append(sysconfig_path.name)

    placeholders = platform_stdlib / "lib-dynload"
    placeholders.mkdir(parents=True)
    for module_path in sorted(module_paths, key=lambda path: path.name):
        module = module_name(module_path)
        placeholder = placeholders / f"{module_path.name[:-3]}.fwork"
        placeholder.write_text(f"Frameworks/{module}.framework/{module}\n", encoding="utf-8")
    return sysconfig_names


def add_runtime_licenses(lock: dict, resource_root: Path) -> None:
    repository_root = Path(__file__).resolve().parents[2]
    for component in lock["components"]:
        if component["name"] != "Expat":
            continue
        source = repository_root / "ThirdPartyLicenses" / "Expat-COPYING"
        if sha256(source) != component["licenseSHA256"]:
            raise ValueError("Expat license does not match runtime-lock.json")
        destination = resource_root / "Licenses" / "Expat-COPYING"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        return
    raise ValueError("Expat is missing from runtime-lock.json")


def load_python_resources(repository_root: Path) -> list[dict]:
    manifest_path = repository_root / "Sources" / "YTDLPKit" / "Resources" / "Python" / "manifest.json"
    resource_root = manifest_path.parent
    resource_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if resource_manifest.get("schemaVersion") != 1:
        raise ValueError("unsupported Python resource manifest schema")
    modules = resource_manifest.get("modules")
    if not isinstance(modules, list) or {module.get("name") for module in modules} != {
        "certifi",
        "yt-dlp",
        "yt-dlp-apple-webkit-jsi",
    }:
        raise ValueError("Python resource manifest must contain the three pinned modules")
    for module in modules:
        resource = resource_root / module["file"]
        if not resource.is_file() or sha256(resource) != module["sha256"]:
            raise ValueError(f"Python resource checksum mismatch: {module['name']}")
    provider = next(module for module in modules if module["name"] == "yt-dlp-apple-webkit-jsi")
    if provider.get("sourceCommit") != "53dcc9df1bdb385ef7c21ddbebe2903195eaab77":
        raise ValueError("unexpected yt-dlp Apple WebKit provider source commit")
    return modules


def sign_frameworks(core: Path, extensions: Path, identity: str) -> None:
    frameworks = [
        core / DEVICE_SLICE / "Python.framework",
        core / SIMULATOR_SLICE / "Python.framework",
    ]
    frameworks.extend(sorted(extensions.glob("*.xcframework/*/*.framework")))
    for framework in frameworks:
        run(
            "codesign",
            "--force",
            "--sign",
            identity,
            "--timestamp=none",
            "--preserve-metadata=identifier",
            str(framework),
        )
        run("codesign", "--verify", "--strict", str(framework))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", required=True, type=Path)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--signing-identity")
    args = parser.parse_args()

    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    repository_root = Path(__file__).resolve().parents[2]
    python_resources = load_python_resources(repository_root)
    expected = lock["python"]["sha256"]
    if sha256(args.archive) != expected:
        raise SystemExit("runtime archive checksum does not match runtime-lock.json")

    output = args.output.resolve()
    if output.exists():
        shutil.rmtree(output)
    staging = output / "staging"
    dist = output / "dist"
    staging.mkdir(parents=True)
    dist.mkdir(parents=True)

    with tempfile.TemporaryDirectory(prefix="ytdlpkit-python-") as temporary:
        extracted = Path(temporary)
        safe_extract(args.archive, extracted)
        upstream = extracted / "Python.xcframework"
        if not upstream.is_dir():
            raise SystemExit("archive does not contain Python.xcframework")

        core = staging / "PythonRuntime.xcframework"
        write_plist(core / "Info.plist", xcframework_plist("Python"))
        for slice_name in (DEVICE_SLICE, SIMULATOR_SLICE):
            copy_framework(
                upstream / slice_name / "Python.framework",
                core / slice_name / "Python.framework",
            )
            write_plist(
                core / slice_name / "Python.framework" / "PrivacyInfo.xcprivacy",
                python_core_privacy_manifest(),
            )

        abi = lock["python"]["abi"]
        device_dir = upstream / DEVICE_SLICE / "lib-arm64" / f"python{abi}" / "lib-dynload"
        sim_arm_dir = upstream / SIMULATOR_SLICE / "lib-arm64" / f"python{abi}" / "lib-dynload"
        sim_x86_dir = upstream / SIMULATOR_SLICE / "lib-x86_64" / f"python{abi}" / "lib-dynload"
        all_device = indexed_modules(device_dir)
        all_sim_arm = indexed_modules(sim_arm_dir)
        all_sim_x86 = indexed_modules(sim_x86_dir)
        if all_device.keys() != all_sim_arm.keys() or all_device.keys() != all_sim_x86.keys():
            raise SystemExit("extension module sets differ between runtime slices")
        missing_exclusions = set(EXCLUDED_EXTENSION_MODULES) - all_device.keys()
        if missing_exclusions:
            raise SystemExit(f"pinned extension exclusions missing upstream: {sorted(missing_exclusions)}")
        device = {name: path for name, path in all_device.items() if name not in EXCLUDED_EXTENSION_MODULES}
        sim_arm = {name: path for name, path in all_sim_arm.items() if name not in EXCLUDED_EXTENSION_MODULES}
        sim_x86 = {name: path for name, path in all_sim_x86.items() if name not in EXCLUDED_EXTENSION_MODULES}

        extension_root = staging / "Extensions"
        for name in sorted(device):
            create_extension_xcframework(
                name,
                device[name],
                sim_arm[name],
                sim_x86[name],
                extension_root / f"{name}.xcframework",
            )

        resources = staging / "PythonRuntimeResources"
        sysconfig_paths = [
            upstream / DEVICE_SLICE / "lib-arm64" / f"python{abi}" / "_sysconfigdata__ios_arm64-iphoneos.py",
            upstream / SIMULATOR_SLICE / "lib-arm64" / f"python{abi}" / "_sysconfigdata__ios_arm64-iphonesimulator.py",
            upstream / SIMULATOR_SLICE / "lib-x86_64" / f"python{abi}" / "_sysconfigdata__ios_x86_64-iphonesimulator.py",
        ]
        sysconfig_names = build_stdlib(
            upstream / "lib" / f"python{abi}",
            resources,
            list(device.values()) + list(sim_arm.values()) + list(sim_x86.values()),
            sysconfig_paths,
        )
        add_runtime_licenses(lock, resources)

        if args.signing_identity:
            sign_frameworks(core, extension_root, args.signing_identity)

    artifacts: list[dict[str, object]] = []
    core_zip = dist / "PythonRuntime.xcframework.zip"
    deterministic_zip(core, core_zip)
    artifacts.append({"kind": "binaryTarget", "name": "PythonRuntime", "file": core_zip.name, "sha256": sha256(core_zip)})

    for extension in sorted(extension_root.glob("*.xcframework")):
        archive = dist / f"{extension.name}.zip"
        deterministic_zip(extension, archive)
        artifacts.append({"kind": "binaryTarget", "name": extension.stem, "file": archive.name, "sha256": sha256(archive)})

    resource_zip = dist / "PythonRuntimeResources.zip"
    deterministic_zip(resources, resource_zip, keep_parent=False)
    artifacts.append({"kind": "resources", "name": "PythonRuntimeResources", "file": resource_zip.name, "sha256": sha256(resource_zip)})

    manifest = {
        "schemaVersion": 1,
        "source": lock["python"],
        "extensionCount": len(device),
        "excludedExtensionModules": list(EXCLUDED_EXTENSION_MODULES),
        "sysconfigDataFiles": sysconfig_names,
        "privacyManifestModules": sorted(PRIVACY_MANIFEST_MODULES),
        "pythonCorePrivacyManifest": {
            "requiredReasonAPIs": {
                "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
                "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
            }
        },
        "signing": {
            "mode": "signed" if args.signing_identity else "unsigned",
            **({"identity": args.signing_identity} if args.signing_identity else {}),
        },
        "pythonResources": python_resources,
        "artifacts": artifacts,
    }
    (dist / "ArtifactManifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    scripts = sorted(
        (path.resolve() for path in Path(__file__).parent.iterdir() if path.suffix in {".py", ".sh"}),
        key=lambda path: path.name,
    )
    materials = [{"uri": lock["python"]["url"], "sha256": lock["python"]["sha256"]}]
    for component in lock["components"]:
        if "privacyManifestURL" in component:
            materials.append(
                {
                    "uri": component["privacyManifestURL"],
                    "sha256": component["privacyManifestSHA256"],
                }
            )
        if "sourceURL" in component and "licenseSHA256" in component:
            materials.append(
                {
                    "uri": component["sourceURL"],
                    "sha256": component["licenseSHA256"],
                }
            )
    for resource in python_resources:
        material = {"uri": resource["source"], "sha256": resource["sha256"]}
        if "sourceCommit" in resource:
            material["sourceCommit"] = resource["sourceCommit"]
        materials.append(material)
    provenance = {
        "schemaVersion": 1,
        "subject": [{"name": item["file"], "sha256": item["sha256"]} for item in artifacts],
        "materials": materials,
        "transformation": "BeeWare iOS support archive to SwiftPM XCFrameworks and Python resources",
        "signing": manifest["signing"],
        "builder": {
            "python": sys.version.split()[0],
            "scripts": [{"path": script.name, "sha256": sha256(script)} for script in scripts],
        },
    }
    (dist / "BuildProvenance.json").write_text(json.dumps(provenance, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    packages = [
        {
            "SPDXID": f"SPDXRef-Package-{index}",
            "name": component["name"],
            "versionInfo": component["version"],
            "downloadLocation": "NOASSERTION",
            "filesAnalyzed": False,
            "licenseConcluded": "NOASSERTION",
            "licenseDeclared": component["license"],
        }
        for index, component in enumerate(lock["components"], start=1)
    ]
    resource_license_ids = {
        "certifi": "MPL-2.0",
        "yt-dlp": "Unlicense",
        "yt-dlp-apple-webkit-jsi": "Apache-2.0",
    }
    resource_packages = [
        {
            "SPDXID": f"SPDXRef-Package-{resource['name']}",
            "name": resource["name"],
            "versionInfo": resource["version"],
            "downloadLocation": resource["source"],
            "filesAnalyzed": False,
            "licenseConcluded": "NOASSERTION",
            "licenseDeclared": resource_license_ids[resource["name"]],
            "checksums": [{"algorithm": "SHA256", "checksumValue": resource["sha256"]}],
            "packageComment": resource["license"],
        }
        for resource in python_resources
    ]
    runtime_package = {
        "SPDXID": "SPDXRef-Package-YTDLPKitRuntime",
        "name": "YTDLPKit embedded runtime",
        "downloadLocation": "NOASSERTION",
        "filesAnalyzed": False,
        "licenseConcluded": "MIT",
        "licenseDeclared": "MIT",
    }
    packages.extend(resource_packages)
    packages.append(runtime_package)
    relationships = [
        {
            "spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES",
            "relatedSpdxElement": runtime_package["SPDXID"],
        }
    ]
    relationships.extend(
        {
            "spdxElementId": "SPDXRef-Package-1",
            "relationshipType": "DEPENDS_ON",
            "relatedSpdxElement": package["SPDXID"],
        }
        for package in packages[1:7]
    )
    relationships.extend(
        {
            "spdxElementId": runtime_package["SPDXID"],
            "relationshipType": "DEPENDS_ON",
            "relatedSpdxElement": package["SPDXID"],
        }
        for package in [packages[0], *resource_packages]
    )
    namespace_digest = hashlib.sha256(
        "".join([lock["python"]["sha256"], *(resource["sha256"] for resource in python_resources)]).encode()
    ).hexdigest()
    sbom = {
        "SPDXID": "SPDXRef-DOCUMENT",
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "name": "YTDLPKit-PythonRuntime",
        "documentNamespace": f"https://spdx.org/spdxdocs/YTDLPKit-PythonRuntime-{namespace_digest}",
        "creationInfo": {
            "created": lock["python"]["releasePublishedAt"],
            "creators": ["Tool: YTDLPKit runtime repackager"],
        },
        "packages": packages,
        "relationships": relationships,
    }
    (dist / "SBOM.spdx.json").write_text(json.dumps(sbom, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    shutil.copy2(args.lock, dist / "runtime-lock.json")


if __name__ == "__main__":
    main()
