import argparse
from collections.abc import Iterator
from functools import partial

import requests
import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from python_kidra.kidra import Service, generate_sub_services, custom_openapi
from python_kidra._version import __version__


app = FastAPI(openapi_url="/v3/api-docs")


class Ports:
    def __init__(self, start: int):
        self.current_int = start
        self.current = str(start)

    def __next__(self) -> str:
        self.current_int += 1
        self.current = str(self.current_int)

        return self.current


ports = Ports(1986)

# the collection of all services to be collected in the kidra
SERVICES: dict[str, Service] = {
    "text-statistics": Service(
        name="text-statistics",
        binary="text-statistics",
        host="localhost",
        port=next(ports),
        post_subdomain="analyze-text",
    ),
    "text-extraction": Service(
        name="text-extraction",
        binary="text-extraction",
        host="localhost",
        port=next(ports),
        post_subdomain="from-url",
    ),
    "disciplines": Service(
        name="disciplines",
        binary="wlo-classification",
        host="localhost",
        port=next(ports),
        post_subdomain="predict_subjects",
    ),
    "topic-assistant-keywords": Service(
        name="topic-assistant-keywords",
        binary="wlo-topic-assistant",
        host="localhost",
        port=next(ports),
        post_subdomain="topics_flat",
        autostart=True,
        boot_timeout=None,
    ),
    "topic-assistant-embeddings": Service(
        name="topic-assistant-embeddings",
        binary="",
        host="localhost",
        port=ports.current,
        post_subdomain="topics2_flat",
        autostart=False,  # already started above
    ),
}


def main():
    # define CLI arguments
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--port", action="store", default=8080, help="Port to listen on", type=int
    )
    parser.add_argument(
        "--host", action="store", default="0.0.0.0", help="Hosts to listen to", type=str
    )
    parser.add_argument(
        "--version",
        action="version",
        version="%(prog)s {version}".format(version=__version__),
    )

    # read passed CLI arguments
    args = parser.parse_args()

    # add all of the defined services
    generate_sub_services(app, SERVICES.values())

    # manually add the wikipedia linking service
    class Data(BaseModel):
        text: str

    class Entity(BaseModel):
        entity: str
        start: int
        end: int
        score: float
        categories: list[str]

    class Result(BaseModel):
        text: str
        entities: list[Entity]
        essentialCategories: list[str]
        version: str = "0.1.0"

    dbpedia_service = Service(
        name="link-wikipedia",
        binary="",
        host="wlo.yovisto.com/services",
        port=None,
        post_subdomain="extract",
        autostart=False,  # not directly integrated in the kidra
    )

    summary = "Collect relevant Wikipedia articles for the given text"

    @app.post(
        f"/{dbpedia_service.name}",
        summary=summary,
        description=f"""
        {summary}

        Parameters
        ----------
        text : str
            The text to be analyzed.

        Returns
        -------
        text : str
            A modified version of the given text,
            where matched phrases are replaced with hyperlinks to their
            corresponding Wikipedia entry.
        entities : list of Entity
            All Wikipedia entries that were matched for the given text.
            Contains the following attributes:

            entity : str
                The name of the entry.
            start : int
                The start position of the phrase that was matched to this entity.
            end : int
                The end position of the phrase that was matched to this entity.
            score : float
                The score (from 0 to 1) of the match.
            categories : list of str
                The German Wikipedia categories associated with this entity.
        essentialCategories : list of str
            A list of German Wikipedia categories that are shared between
            multiple associated entities.
        version : str
            The version of the Wikipedia linking service.
            Currently a placeholder.
        """,
    )
    def fun(data: Data) -> Result:
        result = requests.post(
            dbpedia_service.post_address,
            # encode as UTF-8 to prevent umlauts etc. causing issues
            data=data.text.encode("utf-8"),
        ).json()

        return Result(
            text=result["text"],
            entities=[
                Entity(
                    entity=ent["entity"],
                    start=ent["start"],
                    end=ent["end"],
                    score=ent["score"],
                    categories=ent["categories"],
                )
                for ent in result["entities"]
            ],
            essentialCategories=result["essentialCategories"],
        )

    # add a ping function
    @app.get("/_ping")
    def _ping():
        pass

    # override the openapi by merging the ones of the sub-services
    app.openapi = partial(custom_openapi, app=app, services=SERVICES.values())

    # start the web service
    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        reload=False,
    )


if __name__ == "__main__":
    main()
