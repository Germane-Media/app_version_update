import 'dart:convert';
import 'dart:developer' show log;
import 'dart:io';

import 'package:app_version_update/data/models/app_version_data.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../values/consts/consts.dart';

/// Fetch version regarding platform.
/// * ```appleId``` unique identifier in Apple Store, if null, we will use your package name.
/// * ```playStoreId``` unique identifier in Play Store, if null, we will use your package name.
/// * ```country``` (iOS only) region of store, if null, we will use 'us'.
Future<AppVersionData> fetchVersion({String? playStoreId, String? appleId, String? country}) async {
  final packageInfo = await PackageInfo.fromPlatform();
  AppVersionData data = AppVersionData();
  if (Platform.isAndroid) {
    data = await fetchAndroid(packageInfo: packageInfo, playStoreId: playStoreId);
  } else if (Platform.isIOS) {
    data = await fetchIOS(
      packageInfo: packageInfo,
      appleId: appleId,
      country: country,
    );
  } else {
    throw "Unknown platform";
  }
  return data;
}

Future<AppVersionData> fetchAndroid({PackageInfo? packageInfo, String? playStoreId}) async {
  playStoreId = playStoreId ?? packageInfo?.packageName;
  final parameters = {
    "id": playStoreId,
  };
  var uri = Uri.https(playStoreAuthority, playStoreUndecodedPath, parameters);
  final response = await http.get(uri, headers: headers).catchError((e) => throw e);
  if (response.statusCode == 200) {
    final String htmlString = response.body;
    if (playStoreId == null) {
      throw "Application id is not provided.";
    }
    String? lastVersion = extractVersionFromHtmlRegexForAndroid(htmlString, playStoreId);

    return AppVersionData(
      // canUpdate: packageInfo.version < lastVersion ? true : false,
      storeVersion: lastVersion,
      storeUrl: uri.toString(),
      localVersion: packageInfo!.version,
      targetPlatform: TargetPlatform.android,
    );
  } else {
    throw "Application not found in Play Store, verify your app id.";
  }
}

Future<AppVersionData> fetchIOS({PackageInfo? packageInfo, String? appleId, String? country}) async {
  assert(appleId != null || packageInfo != null, 'One between appleId or packageInfo must not be null');
  var parameters = (appleId != null) ? {"id": appleId} : {'bundleId': packageInfo?.packageName};
  if (country != null) {
    parameters['country'] = country;
  }
  parameters['version'] = '2';
  var uri = Uri.https(appleStoreAuthority, '/lookup', parameters);
  final response = await http.get(uri, headers: headers);
  if (response.statusCode == 200) {
    final jsonResult = json.decode(response.body);
    final List results = jsonResult['results'];
    if (results.isEmpty) {
      throw "Application not found in Apple Store, verify your app id.";
    } else {
      return AppVersionData(
          storeVersion: jsonResult['results'].first['version'],
          storeUrl: jsonResult['results'].first['trackViewUrl'],
          localVersion: packageInfo?.version,
          targetPlatform: TargetPlatform.iOS);
    }
  } else {
    return throw "Application not found in Apple Store, verify your app id.";
  }
}

// Fixed regex patterns with proper escaping
String? extractVersionFromHtmlRegexForAndroid(String htmlResponse, String key) {
  try {
    if (htmlResponse.isEmpty) {
      return null;
    }
    log("htmlResponse is not empty");

    RegExp bodyRegex = RegExp(r'<body[^>]*>([\s\S]*?)</body>', caseSensitive: false);
    var bodyMatch = bodyRegex.firstMatch(htmlResponse);

    if (bodyMatch == null) {
      log('No body tag found using regex');
      return null;
    }
    log("body is not empty");

    String bodyContent = bodyMatch.group(1)!;

    RegExp scriptRegex = RegExp(r'<script[^>]*>([\s\S]*?)</script>', caseSensitive: false);
    var scriptMatches = scriptRegex.allMatches(bodyContent);
    log("scriptMatches size ${scriptMatches.length}");

    List<String> matchingScriptContents = [];

    for (var match in scriptMatches) {
      String scriptContent = match.group(1) ?? '';
      if (scriptContent.contains(key) && scriptContent.contains("AF_initDataCallback")) {
        // log("Found this script that has our KEY :\n $scriptContent");
        matchingScriptContents.add(scriptContent);
      }
    }

    log('Found ${matchingScriptContents.length} script(s) containing key: "$key"');

    // Fixed regex patterns with proper escaping
    // Pattern 1: ["x.x.x"] or ['x.x.x'] (array format)
    RegExp pattern1 = RegExp(r'\[\"(\d+\.\d+\.\d+)\"\]');

    // Pattern 2: ['x.x.x'] (array format with single quotes)
    RegExp pattern2 = RegExp(r"\[\'(\d+\.\d+\.\d+)\'\]");

    // Pattern 3: "x.x.x" (double quotes)
    RegExp pattern3 = RegExp(r'\"(\d+\.\d+\.\d+)\"');

    // Pattern 4: 'x.x.x' (single quotes)
    RegExp pattern4 = RegExp(r"\'(\d+\.\d+\.\d+)\'");

    // Pattern 5: Just the version number (fallback)
    RegExp pattern5 = RegExp(r'\b\d+\.\d+\.\d+\b');

    List<RegExp> patterns = [pattern1, pattern2, pattern3, pattern4, pattern5];

    for (var pattern in patterns) {
      // log('Trying pattern: ${pattern.pattern}');
      for (var scriptContent in matchingScriptContents) {
        var versionMatch = pattern.firstMatch(scriptContent);
        if (versionMatch != null) {
          String foundVersion = versionMatch.groupCount >= 1 ? versionMatch.group(1)! : versionMatch.group(0)!;
          log('Successfully extracted version pattern: $foundVersion');
          log('Using pattern: ${pattern.pattern}');
          return foundVersion;
        }
      }
    }

    log('No version pattern found with any pattern');
    return null;
  } catch (e) {
    log('Error in regex extraction: $e');
    return null;
  }
}
