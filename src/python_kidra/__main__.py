import argparse
from collections.abc import Iterator
from functools import partial

import requests
import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from python_kidra.webservice import Service, generate_sub_services, custom_openapi
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
    dbpedia_service = Service(
        name="link-wikipedia",
        binary="",
        host="wlo.yovisto.com/services",
        port=None,
        post_subdomain="extract",
        autostart=False,  # not directly integrated in the kidra
    )

    @app.post(f"/{dbpedia_service.name}")
    def fun(data: dict) -> dict:
        result = requests.post(
            dbpedia_service.post_address,
            # encode as UTF-8 to prevent umlauts etc. causing issues
            data=data["text"].encode("utf-8"),
        ).json()

        # the service does not provide a version
        result["version"] = "0.1.0"
        return result

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
