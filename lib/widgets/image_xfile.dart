import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Prévisualisation d'une image fraîchement sélectionnée (XFile), compatible
/// WEB + iOS + Android : lit les octets (pas de dart:io File, qui crashe en
/// navigateur) et affiche via Image.memory.
class ImageXFile extends StatelessWidget {
  final XFile xfile;
  final double? width;
  final double? height;
  final BoxFit? fit;
  const ImageXFile(this.xfile,
      {super.key, this.width, this.height, this.fit});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: xfile.readAsBytes(),
      builder: (context, s) {
        if (!s.hasData) {
          return SizedBox(
              width: width,
              height: height,
              child: const Center(
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))));
        }
        return Image.memory(s.data!, width: width, height: height, fit: fit);
      },
    );
  }
}
