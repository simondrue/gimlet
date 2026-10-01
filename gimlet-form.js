// A small form: one window with labeled fields, for the custom order and the settings.
// Usage: osascript -l JavaScript gimlet-form.js <title> <emoji> <ok button> <extra button> <error> \
//            <label> <value> <hint> [<label> <value> <hint> ...]
// Prints the field values joined by "|" on OK; exits with 1 on Cancel, 2 on the extra button
// (left out when empty).
ObjC.import('AppKit');
ObjC.import('stdlib');

function run(argv) {
    const [title, emoji, ok, extra, error, ...rest] = argv;
    const rows = [];
    for (let i = 0; i < rest.length; i += 3) rows.push(rest.slice(i, i + 3));
    // Brings the window to the front, even when run from the menu bar.
    $.NSApplication.sharedApplication;
    $.NSApp.setActivationPolicy($.NSApplicationActivationPolicyAccessory);
    $.NSApp.activateIgnoringOtherApps(true);

    const alert = $.NSAlert.alloc.init;
    alert.messageText = title;
    alert.informativeText = error;
    // The emoji as the icon, in place of the app's.
    const icon = $.NSImage.alloc.initWithSize($.NSMakeSize(64, 64));
    const attrs = $.NSMutableDictionary.dictionary;
    attrs.setObjectForKey($.NSFont.systemFontOfSize(52), 'NSFont');  // NSFontAttributeName
    icon.lockFocus;
    $.NSString.alloc.initWithUTF8String(emoji).drawAtPointWithAttributes($.NSMakePoint(0, 0), attrs);
    icon.unlockFocus;
    alert.icon = icon;
    alert.addButtonWithTitle(ok);
    alert.addButtonWithTitle('Cancel');
    if (extra) alert.addButtonWithTitle(extra);

    const rowH = 30, labelW = 90, fieldW = 170, w = 340;
    const view = $.NSView.alloc.initWithFrame($.NSMakeRect(0, 0, w, rows.length * rowH));
    const fields = rows.map(([label, value, unit], i) => {
        const y = (rows.length - 1 - i) * rowH;
        const name = $.NSTextField.labelWithString(label);
        name.frame = $.NSMakeRect(0, y + 3, labelW, 20);
        const field = $.NSTextField.textFieldWithString(value);
        field.frame = $.NSMakeRect(labelW + 5, y, fieldW, 24);
        const hint = $.NSTextField.labelWithString(unit);
        hint.frame = $.NSMakeRect(labelW + fieldW + 12, y + 3, w - labelW - fieldW - 12, 20);
        hint.textColor = $.NSColor.secondaryLabelColor;
        [name, field, hint].forEach(v => view.addSubview(v));
        return field;
    });
    // Tab moves down the fields.
    fields.forEach((f, i) => f.nextKeyView = fields[(i + 1) % fields.length]);
    alert.accessoryView = view;
    alert.layout;
    alert.window.initialFirstResponder = fields[0];

    const button = alert.runModal;
    if (button === $.NSAlertSecondButtonReturn) $.exit(1);
    if (button === $.NSAlertThirdButtonReturn) $.exit(2);
    return fields.map(f => f.stringValue.js.trim()).join('|');
}
