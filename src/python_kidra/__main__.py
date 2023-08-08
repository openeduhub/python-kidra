from collections.abc import Iterator
import cherrypy
import requests
from python_kidra.webservice import Service, KidraService


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
        post_subdomain="topics",
        autostart=True,
        boot_timeout=None,
    ),
    "topic-assistant-embeddings": Service(
        name="topic-assistant-embeddings",
        binary="",
        host="localhost",
        port=ports.current,
        post_subdomain="topics2",
        autostart=False,  # already started above
    ),
    "dbpedia": Service(
        name="link-wikipedia",
        binary="",
        host="wlo.yovisto.com/services",
        port=None,
        post_subdomain="extract",
        autostart=False,  # not directly integrated in the kidra
    ),
}


def main():
    # listen to requests from any incoming IP address
    cherrypy.server.socket_host = "0.0.0.0"
    webservice = KidraService(SERVICES.values())

    # override post function for extract-categories,
    # because it expects a string, not a JSON object
    service = SERVICES["dbpedia"]

    def fun(data: dict) -> dict:
        result = requests.post(
            service.api_address,
            # encode as UTF-8 to prevent umlauts etc. causing issues
            data=data["text"].encode("utf-8"),
        ).json()

        # the service does not provide a version
        result["version"] = "0.1.0"
        return result

    webservice.post_request_funs["extract-categories"] = fun

    # start the web service
    cherrypy.quickstart(webservice)


if __name__ == "__main__":
    main()
