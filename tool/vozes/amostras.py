"""Gera amostras de vozes femininas pt-BR naturais para o usuário escolher."""
import asyncio, json, sys
import edge_tts

TEXTO = ("Vamos começar! Você consegue! ... "
         "Quilômetro 3. Tempo: 16 minutos e 20 segundos. "
         "Pace: 5 minutos e 26 segundos por quilômetro. "
         "Você está indo muito bem! ... "
         "Corrida finalizada. 5 quilômetros em 27 minutos. Mandou bem!")

async def main(out):
    vozes = [v for v in await edge_tts.list_voices()
             if v["Locale"] == "pt-BR" and v["Gender"] == "Female"]
    print(json.dumps([v["ShortName"] for v in vozes]))
    for v in vozes:
        nome = v["ShortName"].replace("pt-BR-", "").replace("Neural", "").lower()
        await edge_tts.Communicate(TEXTO, v["ShortName"]).save(f"{out}/voz-{nome}.mp3")

asyncio.run(main(sys.argv[1]))
