#!/usr/bin/env python3
"""Regenerate SwiftUI geometry and Apple icon assets from WorkspaceMark.svg.
Run on macOS with Xcode: python3 Design/generate_brand_assets.py
"""
import json
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESIGN = ROOT / 'Design'
CATALOG = ROOT / 'Assets.xcassets'
BLUE = '#2496ED'

def swift_path(d):
    tokens = re.findall(r'[MQHVZ]|-?\d+(?:\.\d+)?', d)
    commands = []
    x = y = 0
    i = 0
    while i < len(tokens):
        op = tokens[i]
        i += 1
        count = {'M': 2, 'Q': 4, 'H': 1, 'V': 1, 'Z': 0}[op]
        v = tokens[i:i + count]
        i += count
        if op == 'M':
            x, y = v
            commands.append(f'p.move(to: CGPoint(x: {x}, y: {y}))')
        elif op == 'Q':
            cx, cy, x, y = v
            commands.append(f'p.addQuadCurve(to: CGPoint(x: {x}, y: {y}), control: CGPoint(x: {cx}, y: {cy}))')
        elif op in ('H', 'V'):
            if op == 'H': x = v[0]
            else: y = v[0]
            commands.append(f'p.addLine(to: CGPoint(x: {x}, y: {y}))')
        else:
            commands.append('p.closeSubpath()')
    return commands

svg = ET.parse(DESIGN / 'WorkspaceMark.svg').getroot()
paths = [el.attrib['d'] for el in svg.iter() if el.tag.endswith('}path')]
assert len(paths) == 3, 'Expected the approved three-layer board symbol'
commands = '\n        '.join(c for d in paths for c in swift_path(d))
source = '''// Generated from Design/WorkspaceMark.svg by Design/generate_brand_assets.py.
// Change the SVG and regenerate to keep onboarding and app icons identical.
import SwiftUI
#if os(macOS)
import AppKit
#endif

enum WorkspaceBrand {
    static let blue = Color(.sRGB, red: 36 / 255, green: 150 / 255, blue: 237 / 255, opacity: 1)
}

struct WorkspaceMark: View {
    @Environment(\\.colorScheme) private var colorScheme
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 222 / 1024)
                .fill(colorScheme == .dark ? WorkspaceBrand.blue : .white)
            WorkspaceLogoShape()
                .fill(colorScheme == .dark ? .white : WorkspaceBrand.blue, style: FillStyle(eoFill: true))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Tierin")
    }
}

struct WorkspaceLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        GEOMETRY
        let scale = min(rect.width, rect.height) / 1024
        return p.applying(CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.midX - 512 * scale,
                                           y: rect.midY - 512 * scale)))
    }
}

#if os(macOS)
extension WorkspaceBrand {
    // Renderer used by the asset generator for older-system icon fallbacks.
    static func icon(pixels: Int, dark: Bool, mac: Bool) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: pixels * 4, bitsPerPixel: 32)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: CGFloat(pixels) / 1024, y: -CGFloat(pixels) / 1024)
        let blue = CGColor(srgbRed: 36 / 255, green: 150 / 255, blue: 237 / 255, alpha: 1)
        context.setFillColor(dark ? blue : CGColor(gray: 1, alpha: 1))
        let rect = mac ? CGRect(x: 96, y: 96, width: 832, height: 832)
                       : CGRect(x: 0, y: 0, width: 1024, height: 1024)
        // iOS supplies the outer mask; macOS legacy icons need their own inset silhouette.
        let radius: CGFloat = mac ? 180 : 0
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        context.setFillColor(dark ? CGColor(gray: 1, alpha: 1) : blue)
        context.addPath(WorkspaceLogoShape().path(in: rect).cgPath)
        context.drawPath(using: .eoFill)
        if !mac {
            let opaque = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: pixels * 3, bitsPerPixel: 24)!
            for pixel in 0..<(pixels * pixels) {
                for channel in 0..<3 { opaque.bitmapData![pixel * 3 + channel] = rep.bitmapData![pixel * 4 + channel] }
            }
            return opaque
        }
        return rep
    }

}
#endif
'''.replace('GEOMETRY', commands)
source_path = ROOT / 'Sources/ProjectBoard/WorkspaceBrand.swift'
source_path.parent.mkdir(parents=True, exist_ok=True)
render_support = source[source.index('#if os(macOS)\nextension WorkspaceBrand'):].removeprefix('#if os(macOS)\n').removesuffix('#endif\n')
source_path.write_text(source[:source.index('#if os(macOS)\nextension WorkspaceBrand')].replace('#if os(macOS)\nimport AppKit\n#endif\n', ''))

items = [dict(filename='AppIcon-1024.png', idiom='universal', platform='ios', size='1024x1024'),
         dict(filename='AppIcon-Dark-1024.png', idiom='universal', platform='ios', size='1024x1024',
              appearances=[dict(appearance='luminosity', value='dark')])]
exports = []
iconset = CATALOG / 'AppIcon.appiconset'
iconset.mkdir(parents=True, exist_ok=True)
for item in items:
    exports.append(dict(path=str(iconset / item['filename']), pixels=1024, dark='appearances' in item, mac=False))
for size in [16,32,128,256,512]:
    for scale in [1,2]:
        filename=f'AppIcon-Mac-{size}@{scale}x.png'
        items.append(dict(filename=filename, idiom='mac', scale=f'{scale}x', size=f'{size}x{size}'))
        exports.append(dict(path=str(iconset / filename), pixels=size*scale, dark=False, mac=True))
# Explicit dark Mac artwork for previews and distribution tooling.
exports.append(dict(path=str(DESIGN/'WorkspaceMarkMac-Dark.png'), pixels=1024, dark=True, mac=True))
exports.append(dict(path=str(DESIGN/'WorkspaceMarkMac-Light.png'), pixels=1024, dark=False, mac=True))
(iconset/'Contents.json').write_text(json.dumps(dict(images=items, info=dict(author='xcode', version=1)), indent=2)+'\n')
for dark in [False,True]:
    variant='Dark' if dark else 'Light'
    ink='#FFFFFF' if dark else BLUE
    bg=BLUE if dark else '#FFFFFF'
    shape=''.join(f'<path fill-rule="evenodd" d="{d}"/>' for d in paths)
    (DESIGN/f'WorkspaceMark-{variant}.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect width="1024" height="1024" rx="222" fill="{bg}"/><g fill="{ink}">{shape}</g></svg>\n')
# Preserve the old design-source filename as the updated Mac export.
(DESIGN/'WorkspaceMarkMac.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect x="96" y="96" width="832" height="832" rx="180" fill="#FFFFFF"/><g fill="{BLUE}" transform="translate(96 96) scale(.8125)">'+''.join(f'<path fill-rule="evenodd" d="{d}"/>' for d in paths)+'</g></svg>\n')
with tempfile.TemporaryDirectory(prefix='workspace-brand-') as temp:
    temp=Path(temp)
    (temp/'exports.json').write_text(json.dumps(exports))
    (temp/'Render.swift').write_text('import SwiftUI\nimport AppKit\n' + render_support + '''

@main struct Render {
    static func main() throws {
        struct Export: Decodable { let path: String; let pixels: Int; let dark: Bool; let mac: Bool }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        for item in try JSONDecoder().decode([Export].self, from: data) {
            let image = WorkspaceBrand.icon(pixels: item.pixels, dark: item.dark, mac: item.mac)
            guard let png = image.representation(using: .png, properties: [:]) else { fatalError("PNG export failed") }
            try png.write(to: URL(fileURLWithPath: item.path))
        }
    }
}''')
    subprocess.run(['xcrun','swiftc',str(source_path),str(temp/'Render.swift'),'-o',str(temp/'render')],check=True)
    subprocess.run([str(temp/'render'),str(temp/'exports.json')],check=True)

icon = ROOT / 'WorkspaceIcon.icon'
(icon / 'Assets').mkdir(parents=True, exist_ok=True)
(icon / 'Assets' / 'WorkspaceMark.svg').write_text((DESIGN / 'WorkspaceMark.svg').read_text())
blue_color = 'extended-srgb:0.14118,0.58824,0.92941,1.00000'
white_color = 'extended-srgb:1.00000,1.00000,1.00000,1.00000'
(icon / 'icon.json').write_text(json.dumps({
    'fill-specializations': [{'value': {'solid': white_color}}, {'appearance': 'dark', 'value': {'solid': blue_color}}],
    'groups': [{
        'layers': [{
            'image-name': 'WorkspaceMark.svg', 'name': 'Project boards',
            'fill-specializations': [{'value': {'solid': blue_color}}, {'appearance': 'dark', 'value': {'solid': white_color}}]
        }],
        'shadow': {'kind': 'neutral', 'opacity': 0},
        'translucency': {'enabled': False, 'value': 0}
    }],
    'supported-platforms': {'squares': 'shared'}
}, indent=2) + '\n')

print(f'Generated shared logo geometry, {len(exports)} PNGs, and light/dark SVGs.')
