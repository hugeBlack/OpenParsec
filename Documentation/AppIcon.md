# Layered app icon

`OpenParsec/AppIcon.icon` is an editable Icon Composer document. It keeps the existing blue extrusion, magenta face, hollow center, and their original 1024-point placement. The two flat artwork layers are traced from the existing AppIcon artwork; Icon Composer supplies the highlights, material, and shadow rather than baking them into the images.

The document includes light and dark backgrounds and per-layer tinted fills. The system derives clear appearances. The original `Assets.xcassets/AppIcon.appiconset` remains unchanged as the raster fallback/source artwork. Both resources intentionally share the primary icon name, `AppIcon`; Xcode gives the Icon Composer document precedence.

Open the package in Icon Composer to edit it. Preview all six renditions with the **Icon Composer application's** `ictool`, not `xcrun ictool` (which is the asset compiler):

```sh
TOOL="$(dirname "$(xcode-select -p)")/Applications/Icon Composer.app/Contents/Executables/ictool"
for rendition in Default Dark TintedLight TintedDark ClearLight ClearDark; do
  "$TOOL" OpenParsec/AppIcon.icon --export-image \
    --output-file "/tmp/OpenParsec-$rendition.png" --platform iOS \
    --rendition "$rendition" --width 512 --height 512 --scale 1 \
    --design-generation 26 --tint-color 0.6 --tint-strength 0.75
done
```

Default and dark retain the original two-tone identity. Tinted/clear use the system's monochrome treatment. Inspect the full-size preview and a 60-point thumbnail before changing the artwork.
