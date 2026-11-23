import subprocess, os
BAND='#2DD4A0'
HEAD=f'''<path d="M-6 22 L-14 -18 L8 6z" fill="#E8762E"/><path d="M-9 14 L-12 -8 L2 6z" fill="#FDF3E7" fill-opacity=".85"/>
<path d="M22 20 L34 -16 L38 14z" fill="#E8762E"/><path d="M26 14 L33 -6 L34 12z" fill="#FDF3E7" fill-opacity=".85"/>
<ellipse cx="14" cy="34" rx="26" ry="22" fill="#E8762E"/>
<path d="M14 40 Q34 38 50 46 Q46 56 30 56 Q16 54 14 40z" fill="#FDF3E7"/>
<ellipse cx="50" cy="47" rx="5" ry="4" fill="#1F1A17"/>
<rect x="-12" y="16" width="52" height="8" rx="4" fill="{BAND}"/><path d="M-12 20 l-10 -4 l2 10z" fill="{BAND}"/>
<path d="M-8 46 Q14 62 34 58" fill="#FDF3E7"/>
<ellipse cx="10" cy="32" rx="4" ry="5.5" fill="#1F1A17"/><ellipse cx="26" cy="32" rx="4" ry="5.5" fill="#1F1A17"/><circle cx="11.5" cy="30" r="1.6" fill="#fff"/><circle cx="27.5" cy="30" r="1.6" fill="#fff"/>
<path d="M30 52 Q36 57 42 52" fill="none" stroke="#1F1A17" stroke-width="2.5" stroke-linecap="round"/>'''
# Sombra suave sob o queixo (volume) — sutil.
SHADOW='<ellipse cx="16" cy="60" rx="24" ry="3.2" fill="#000" opacity=".22"/>'
# Centro visual da cabeça no desenho (unidades): (15, 21); área visível = 110 unidades.
CX, CY, SPAN = 15, 21, 110
def head_at(cx, cy, size):
    k = size / SPAN
    return f'<g transform="translate({cx - CX*k:.3f} {cy - CY*k:.3f}) scale({k:.5f})">{SHADOW}{HEAD}</g>'
def bg_defs(x, y, w, h):
    # Grafite com luz menta vinda de baixo (Luz 2).
    gx, gy = x + w*0.5, y + h*1.08
    r = ((w*0.5)**2 + (h*1.08)**2) ** 0.5 * 0.66
    return f'''<defs>
<linearGradient id="g" x1="{x}" y1="{y}" x2="{x+w*0.68}" y2="{y+h}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#3A4555"/><stop offset="1" stop-color="#1A212B"/></linearGradient>
<radialGradient id="l" cx="{gx}" cy="{gy}" r="{r}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#4DE8B4" stop-opacity=".78"/><stop offset=".55" stop-color="#3DDBA4" stop-opacity=".28"/><stop offset="1" stop-color="#3DDBA4" stop-opacity="0"/></radialGradient>
<linearGradient id="t" x1="0" y1="{y}" x2="0" y2="{y+h*0.5}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#fff" stop-opacity=".07"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
</defs>'''
def svg(w, h, body): return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">{body}</svg>'
# Ícone tradicional (96, cantos arredondados).
legacy = svg(96, 96, bg_defs(0, 0, 96, 96) +
  '<clipPath id="c"><rect width="96" height="96" rx="22"/></clipPath><g clip-path="url(#c)">'
  '<rect width="96" height="96" fill="url(#g)"/><rect width="96" height="96" fill="url(#l)"/><rect width="96" height="48" fill="url(#t)"/>'
  + head_at(48, 48, 96) + '</g>')
# Adaptável: camadas 108 com área visível central de 72.
background = svg(108, 108, bg_defs(18, 18, 72, 72) +
  '<rect width="108" height="108" fill="url(#g)"/><rect width="108" height="108" fill="url(#l)"/><rect width="108" height="54" fill="url(#t)"/>')
foreground = svg(108, 108, head_at(54, 54, 72))
# Monocromático (ícones temáticos): silhueta com olhos, nariz e faixa vazados.
MONO = '''<mask id="m"><g fill="#fff"><path d="M-6 22 L-14 -18 L8 6z"/><path d="M22 20 L34 -16 L38 14z"/><ellipse cx="14" cy="34" rx="26" ry="22"/>
<path d="M14 40 Q34 38 50 46 Q46 56 30 56 Q16 54 14 40z"/><path d="M-8 46 Q14 62 34 58 L14 40z"/></g>
<g fill="#000"><ellipse cx="10" cy="32" rx="4" ry="5.5"/><ellipse cx="26" cy="32" rx="4" ry="5.5"/>
<rect x="-12" y="17.5" width="52" height="5" rx="2.5"/></g>
<path d="M30 52 Q36 57 42 52" fill="none" stroke="#000" stroke-width="2.5" stroke-linecap="round"/></mask>'''
k = 72 / SPAN
mono = svg(108, 108, f'<defs>{MONO}</defs><g transform="translate({54 - CX*k:.3f} {54 - CY*k:.3f}) scale({k:.5f})"><rect x="-40" y="-40" width="120" height="120" fill="#fff" mask="url(#m)"/></g>')
files = {'legacy': legacy, 'background': background, 'foreground': foreground, 'monochrome': mono}
for n, s in files.items():
    open(f'{n}.svg', 'w').write(s)
dens = {'mdpi': (48, 108), 'hdpi': (72, 162), 'xhdpi': (96, 216), 'xxhdpi': (144, 324), 'xxxhdpi': (192, 432)}
out = '/home/claude/pace._/platform/android/res'
for d, (lg, ad) in dens.items():
    p = f'{out}/mipmap-{d}'
    os.makedirs(p, exist_ok=True)
    subprocess.run(['rsvg-convert', '-w', str(lg), '-h', str(lg), 'legacy.svg', '-o', f'{p}/ic_launcher.png'], check=True)
    for n in ['background', 'foreground', 'monochrome']:
        subprocess.run(['rsvg-convert', '-w', str(ad), '-h', str(ad), f'{n}.svg', '-o', f'{p}/ic_launcher_{n}.png'], check=True)
# Prévias para conferir.
subprocess.run(['rsvg-convert', '-w', '384', 'legacy.svg', '-o', 'prev_legacy.png'], check=True)
for n in ['background', 'foreground', 'monochrome']:
    subprocess.run(['rsvg-convert', '-w', '432', f'{n}.svg', '-o', f'prev_{n}.png'], check=True)
