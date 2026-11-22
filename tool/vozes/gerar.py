"""Grava todas as falas do PACE com a voz natural escolhida (Francisca).

Cada trecho vira um MP3 em out/<chave>.mp3. A chave é o texto normalizado,
igual à função Speech.key em lib/services/speech.dart.
"""
import asyncio, os, re, subprocess, sys, unicodedata
import edge_tts

VOZ = "pt-BR-FranciscaNeural"
RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def chave(s: str) -> str:
    s = unicodedata.normalize("NFD", s.lower())
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9]+", "_", s).strip("_")


U = ("zero um dois três quatro cinco seis sete oito nove dez onze doze treze quatorze quinze "
     "dezesseis dezessete dezoito dezenove").split()
D = "_ _ vinte trinta quarenta cinquenta sessenta setenta oitenta noventa".split()


def ext(n: int, fem=False) -> str:
    if n == 100:
        return "cem"
    if n < 20:
        w = U[n]
    else:
        w = D[n // 10] + ("" if n % 10 == 0 else " e " + U[n % 10])
    if fem:
        w = re.sub(r"\bum$", "uma", w)
        w = re.sub(r"\bdois$", "duas", w)
    return w


def trechos():
    """(texto exibido -> texto falado)"""
    t = {}
    # Frases do Guará faladas durante a corrida (mapas energetic e gentle).
    src = open(os.path.join(RAIZ, "lib/domain/coach.dart"), encoding="utf-8").read()
    corpo = src[src.index("energetic = {"):src.index("static const daily")]
    for m in re.finditer(r"'((?:[^'\\]|\\.)*)'", corpo):
        f = m.group(1).replace("\\'", "'")
        t[f] = f
    for f in ["Corrida iniciada.", "Corrida pausada.", "Corrida retomada.", "Retomando.",
              "Pausa automática.", "Corrida encerrada.", "Meta atingida!", "Tempo",
              "Último quilômetro em", "Pace médio",
              "Bora! Mais um quilômetro. Você está mandando bem."]:
        t[f] = f
    for n in range(1, 101):
        t[f"{n} {'quilômetro' if n == 1 else 'quilômetros'}."] = f"{ext(n)} {'quilômetro' if n == 1 else 'quilômetros'}."
        t[f"Volta {n}."] = f"Volta {ext(n)}."
    for n in range(1, 10):
        t[f"{n} {'hora' if n == 1 else 'horas'}"] = f"{ext(n, True)} {'hora' if n == 1 else 'horas'}"
    for n in range(1, 60):
        w = "minuto" if n == 1 else "minutos"
        t[f"{n} {w}"] = f"{ext(n)} {w}"
        t[f"e {n} {w}"] = f"e {ext(n)} {w}"
    for n in range(0, 60):
        w = "segundo" if n == 1 else "segundos"
        t[f"{n} {w}"] = f"{ext(n)} {w}"
        if n:
            t[f"e {n} {w}"] = f"e {ext(n)} {w}"
    for n in range(0, 101):
        t[f"{n} vírgula"] = f"{ext(n)} vírgula"
    for n in range(0, 100):
        t[f"{n:02d} quilômetros."] = (f"zero {ext(n)}" if n < 10 else ext(n)) + " quilômetros."
    return t


async def gravar(out, k, falado, sem):
    final = os.path.join(out, k + ".mp3")
    bruto = os.path.join(out, k + ".raw.mp3")
    async with sem:
        for tentativa in range(5):
            try:
                await edge_tts.Communicate(falado, VOZ).save(bruto)
                if os.path.getsize(bruto) > 0:
                    break
            except Exception as e:
                print("retry", k, e)
            await asyncio.sleep(2 + tentativa * 3)
        else:
            raise RuntimeError("falhou: " + k)
    # Corta o silêncio das pontas e deixa uma pausa curta no fim:
    # maior depois de frase completa, mínima entre pedaços de número.
    pausa = 0.22 if falado.rstrip()[-1] in ".!?" else 0.05
    af = ("silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
          "silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
          f"apad=pad_dur={pausa}")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", bruto, "-af", af,
                    "-ac", "1", "-ar", "24000", "-b:a", "48k", final], check=True)
    os.remove(bruto)


async def main(out):
    os.makedirs(out, exist_ok=True)
    t = trechos()
    chaves = {}
    for exib, fal in t.items():
        k = chave(exib)
        assert k not in chaves or chaves[k] == fal, (k, exib)
        chaves[k] = fal
    print(len(chaves), "trechos")
    sem = asyncio.Semaphore(6)
    await asyncio.gather(*(gravar(out, k, f, sem) for k, f in chaves.items()))


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1]))
