// Draws the menu bar pill: a rounded box with a coloured dot and a short text.
// Usage: osascript -l JavaScript gimlet-pill.js <text> <dot #hex> <text #hex> <out.png>
ObjC.import('AppKit');

function run(argv) {
    const [text, dot, fg, out] = argv;
    const color = (hex, alpha) => {
        const n = parseInt(hex.slice(1), 16);
        return $.NSColor.colorWithSRGBRedGreenBlueAlpha((n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255, alpha);
    };

    const font = $.NSFont.monospacedDigitSystemFontOfSizeWeight(11, 0.23);  // medium
    const attrs = $.NSMutableDictionary.dictionary;
    attrs.setObjectForKey(font, 'NSFont');  // NSFontAttributeName
    attrs.setObjectForKey(color(fg, 1), 'NSColor');  // NSForegroundColorAttributeName
    const label = $.NSString.alloc.initWithUTF8String(text);
    const size = label.sizeWithAttributes(attrs);

    const h = 16, dotSize = 7, pad = 6, gap = 4, scale = 2;
    const w = Math.ceil(pad + dotSize + gap + size.width + pad);

    // Drawn at 2x for Retina; setSize makes it show at w x h points.
    const rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
        null, w * scale, h * scale, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0);
    rep.setSize($.NSMakeSize(w, h));
    $.NSGraphicsContext.saveGraphicsState;
    $.NSGraphicsContext.setCurrentContext($.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep));

    const pill = $.NSBezierPath.bezierPathWithRoundedRectXRadiusYRadius(
        $.NSMakeRect(0.5, 0.5, w - 1, h - 1), (h - 1) / 2, (h - 1) / 2);
    color(fg, 0.1).setFill;
    pill.fill;
    color(fg, 0.4).setStroke;
    pill.setLineWidth(1);
    pill.stroke;

    color(dot, 1).setFill;
    $.NSBezierPath.bezierPathWithOvalInRect($.NSMakeRect(pad, (h - dotSize) / 2, dotSize, dotSize)).fill;
    label.drawAtPointWithAttributes($.NSMakePoint(pad + dotSize + gap, (h - size.height) / 2), attrs);

    $.NSGraphicsContext.restoreGraphicsState;
    rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $()).writeToFileAtomically(out, true);
}
