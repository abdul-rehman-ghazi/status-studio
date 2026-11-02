/// The first frame of [videoPath] as a 270-wide JPEG for the Recent list.
List<String> thumbnailArguments({
  required String videoPath,
  required String outputPath,
}) {
  return [
    '-y',
    '-ss',
    '0',
    '-i',
    videoPath,
    '-frames:v',
    '1',
    '-vf',
    'scale=270:-2',
    outputPath,
  ];
}
