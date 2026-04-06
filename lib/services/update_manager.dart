import 'dart:convert';
import 'dart:io';

import 'package:apk_installer/apk_installer.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:system_info2/system_info2.dart';

import '/utils/global_vars.dart';

/// Pass the raw old and new version strings.
/// Returns true if the new version is semantically higher
bool newVersionIsHigher(String oldVersion, String newVersion) {
  logger.i("Checking if $newVersion is higher than $oldVersion");
  List<int> oldVersionList = [];
  List<int> newVersionList = [];

  try {
    oldVersionList =
        oldVersion.replaceAll("v", "").split('.').map(int.parse).toList();
    newVersionList =
        newVersion.replaceAll("v", "").split('.').map(int.parse).toList();
  } on FormatException {
    throw Exception("Invalid version format. Can't split into 3 integers");
  }

  // make sure both lists are exactly 3 elements long
  if (oldVersionList.length != 3 || newVersionList.length != 3) {
    throw Exception("Invalid version format. VersionList not exactly 3 long");
  }

  // compare versions
  for (int i = 0; i < 3; i++) {
    if (newVersionList[i] != oldVersionList[i]) {
      return newVersionList[i] > oldVersionList[i];
    }
  }
  return false;
}

class UpdateManager extends ChangeNotifier {
  String? latestTag;
  String? latestChangeLog;
  String downloadLink = "https://download.hedon-haven.top";
  double downloadProgress = 0.0;

  /// This function will both check if an update is available and download the changelog
  Future<bool> updateAvailable() async {
    // Check if using linux
    if (Platform.isLinux ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isIOS) {
      logger
          .w("Auto-updates not yet supported for ${Platform.operatingSystem}!");
      return false;
    }

    // Check if connected to the internet
    if ((await (Connectivity().checkConnectivity()))
        .contains(ConnectivityResult.none)) {
      // Don't throw exception, to avoid popping up in offline mode
      logger.w("No internet connection, canceling update check");
      return false;
    }

    // Get current version
    String localVersion = packageInfo.version;
    // get remote version
    final responseVersion =
        await client.get(Uri.parse("https://changelog.hedon-haven.top/latest"));
    if (responseVersion.statusCode != 200) {
      throw Exception("Couldn't fetch latest version");
    }
    latestTag = responseVersion.body;
    // Get latest changelog
    final responseChangelog = await client
        .get(Uri.parse("https://changelog.hedon-haven.top/$latestTag"));
    if (responseChangelog.statusCode != 200) {
      throw Exception("Couldn't fetch $latestTag changelog");
    }
    latestChangeLog = responseChangelog.body.trim();

    try {
      // compare versions
      if (newVersionIsHigher(localVersion, latestTag!)) {
        logger.i("Local version is lower, update available!");
        return true;
      } else {
        logger.i(
            "Local version matches/higher remote version, no update available");
        return false;
      }
    } catch (e, st) {
      logger.e("Error checking for updates: $e\n$st");
      return false;
    }
  }

  Future<void> downloadAndInstallUpdate(String releaseTag) async {
    // Determine platform
    String platform = Platform.operatingSystem;
    String arch = SysInfo.kernelArchitecture.toString().toLowerCase();
    String fileExt;
    switch (platform) {
      case "android":
        fileExt = "apk";
        break;
      //case "ios":
      //  fileExt = "";
      //  break;
      case "linux":
        throw Exception("Linux updates are handled via flatpak!");
      //case "macos":
      //  fileExt = "";
      //  break;
      //case "windows":
      //  fileExt = "";
      //  break;
      default:
        throw Exception("Unsupported platform");
    }
    logger.i("Downloading $releaseTag update for $platform-$arch.$fileExt");
    // To allow tracking download progress, send GET requests first
    // and then start downloading
    Uri binaryUri = Uri.parse("$downloadLink/$releaseTag/"
        "$platform-$arch.$fileExt");
    Uri checksumUri = Uri.parse("$downloadLink/"
        "$releaseTag/checksums.json");
    logger.i("GET-ting $binaryUri");
    final binaryResponse = await client.send(http.Request('GET', binaryUri));
    logger.i("GET-ting $checksumUri");
    final checksumResponse =
        await client.send(http.Request('GET', checksumUri));
    if (binaryResponse.reasonPhrase != "OK") {
      logger.e("Binary GET request failed, aborting update");
      throw Exception("$binaryUri binary GET request failed");
    }
    if (checksumResponse.reasonPhrase != "OK") {
      logger.e("Checksum.json GET request failed, aborting update");
      throw Exception("$checksumUri Checksum.json GET request failed");
    }
    logger.i("Total binary download size: ${binaryResponse.contentLength}");

    int receivedDownload = 0;
    List<int> downloadedBytes = [];
    await for (var value in binaryResponse.stream) {
      downloadedBytes.addAll(value);
      receivedDownload += value.length;
      downloadProgress = receivedDownload / binaryResponse.contentLength!;
      notifyListeners();
    }
    // simply download checksum without tracking
    Map<String, dynamic> remoteChecksums = jsonDecode((await client
            .get(Uri.parse("$downloadLink/$releaseTag/checksums.json")))
        .body);

    // Get the checksum for the corresponding binary
    String binaryChecksum = remoteChecksums["$platform-$arch.$fileExt"]!;

    // save to cache dir and install
    Directory dir = await getApplicationCacheDirectory();
    logger.i("Checking binary checksum");
    if (binaryChecksum != sha256.convert(downloadedBytes).toString()) {
      logger.e("Checksums do not match, aborting update");
      throw Exception("Checksums do not match");
    }
    logger.i("Checksums match, continuing update");
    logger.i("Saving update file to ${dir.path}/hedon_haven-update.$fileExt");
    await File('${dir.path}/hedon_haven-update.$fileExt')
        .writeAsBytes(downloadedBytes);
    logger.i("Prompting user to update");
    switch (platform) {
      case "android":
        await _installAndroid(dir.path);
        break;
      //case "ios":
      //  fileExt = "";
      //  break;
      case "linux":
        throw Exception("Linux updates are handled via flatpak!");
      //case "macos":
      //  fileExt = "";
      //  break;
      //case "windows":
      //  fileExt = "";
      //  break;
      default:
        throw Exception("Unsupported platform");
    }
  }

  Future<void> _installAndroid(String pathToBinary) async {
    try {
      await ApkInstaller.installApk(
          filePath: "$pathToBinary/hedon_haven-update.apk");
      logger.i("Apk installed");
    } catch (e) {
      logger.e("Android system failed to install update with: $e");
      rethrow;
    }
  }
}
