// SPDX-License-Identifier: GPL-3.0-only
const supportedPlatforms = {'windows', 'android', 'macos', 'ios', 'linux'};

String platformLabel(String os) => switch (os.toLowerCase()) {
  'windows' => 'Windows',
  'android' => 'Android',
  'macos' => 'macOS',
  'ios' => 'iOS',
  'linux' => 'Linux',
  _ => os.isEmpty ? '未知' : os,
};

// Existing clients include unknown capabilities in their signature verification.
String? platformFromCapabilities(Set<String> capabilities) {
  final platforms = capabilities
      .where((value) => value.startsWith('os:'))
      .map((value) => value.substring(3))
      .where(supportedPlatforms.contains)
      .toSet();
  return platforms.length == 1 ? platforms.single : null;
}
