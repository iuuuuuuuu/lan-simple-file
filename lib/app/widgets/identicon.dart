// SPDX-License-Identifier: GPL-3.0-only
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:identicon_dart/identicon_dart.dart' as generator;
import 'package:image/image.dart' as image;

final _identicons = <String, Future<Uint8List>>{};

/// Package-generated GitHub identicons with one cell of padding on every side.
Future<Uint8List> buildIdenticonPng(String peerId, {int size = 420}) {
  if (size < 7) throw ArgumentError.value(size, 'size');
  final key = '$size:$peerId';
  final existing = _identicons[key];
  if (existing != null) return existing;
  if (_identicons.length >= 128) _identicons.remove(_identicons.keys.first);
  final future = SynchronousFuture(_renderPng(peerId, size));
  _identicons[key] = future;
  return future;
}

Uint8List _renderPng(String seed, int size) {
  final cell = size ~/ 7;
  final icon = generator.Identicon(value: seed, size: cell * 5);
  final bytes = Uri.parse(icon.toBase64()).data!.contentAsBytes();
  final content = image.decodePng(bytes)!;
  final padded = image.Image(width: size, height: size);
  image.fill(padded, color: image.ColorRgb8(255, 255, 255));
  final padding = (size - content.width) ~/ 2;
  image.compositeImage(padded, content, dstX: padding, dstY: padding);
  return Uint8List.fromList(image.encodePng(padded));
}

class Identicon extends StatefulWidget {
  const Identicon({
    super.key,
    required this.peerId,
    this.size = 40,
    this.radius,
  });

  final String peerId;
  final double size;
  final double? radius;

  @override
  State<Identicon> createState() => _IdenticonState();
}

class _IdenticonState extends State<Identicon> {
  late Future<Uint8List> _image;

  @override
  void initState() {
    super.initState();
    _image = buildIdenticonPng(widget.peerId);
  }

  @override
  void didUpdateWidget(Identicon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peerId != widget.peerId) {
      _image = buildIdenticonPng(widget.peerId);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius ?? widget.size * 0.16),
      child: FutureBuilder<Uint8List>(
        future: _image,
        builder: (context, snapshot) => snapshot.hasData
            ? Image.memory(
                snapshot.data!,
                width: widget.size,
                height: widget.size,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              )
            : const ColoredBox(color: Colors.white),
      ),
    ),
  );
}

class PeerAvatar extends StatelessWidget {
  const PeerAvatar({
    super.key,
    required this.peerId,
    this.avatarBytes,
    this.size = 40,
    this.radius,
  });

  final String peerId;
  final Uint8List? avatarBytes;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final bytes = avatarBytes;
    if (bytes == null || bytes.isEmpty) {
      return Identicon(peerId: peerId, size: size, radius: radius);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size * 0.16),
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            Identicon(peerId: peerId, size: size, radius: radius),
      ),
    );
  }
}
