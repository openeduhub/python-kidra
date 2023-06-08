from typing import Any, Optional
import text_statistics.stats as stats
from text_statistics.grab_content import grab_content
import pyphen

DEFAULT_PYPHEN_DIC = pyphen.Pyphen(lang="de_DE")


def analyze_text(data: dict[str, Any]) -> Optional[dict[str, Any]]:
    # only support german language for now
    target_language = "de"
    pyphen_dic = DEFAULT_PYPHEN_DIC

    # if the text was given, use that
    if "text" in data:
        text = data["text"]
    # otherwise, crawl the text from the given url
    elif "url" in data:
        url = data["url"]
        text = grab_content(url, favor_precision=True, target_language=target_language)
        # no content could be grabbed
        if not text:
            return None
    # one of text or url has to be given
    else:
        return None

    reading_speed = data.get("reading_speed", 200.0)

    score = stats.calculate_flesch_ease(text, pyphen_dic=pyphen_dic)
    classification = stats.classify_from_flesch_ease(score)
    reading_time = stats.predict_reading_time(
        text=text,
        func=stats.initial_adjust_func,
        dic=pyphen_dic,
        reading_speed=reading_speed,
        score=score,
    )

    return {
        "flesh-ease": score,
        "classification": classification,
        "reading-time": reading_time * 60,
        "text": text,
    }
