import cherrypy
import requests
from python_kidra.webservice import Service, KidraService

# the collection of all services to be collected in the kidra
SERVICES: list[Service] = [
    Service(
        name="text-statistics",
        binary="text-statistics",
        host="localhost",
        port="19867",
        post_subdomain="analyze-text",
    ),
    Service(
        name="topic-assistant-keywords",
        binary="wlo-topic-assistant",
        host="localhost",
        port="19868",
        post_subdomain="topics",
        autostart=True,
        boot_timeout=None,
    ),
    Service(
        name="topic-assistant-embeddings",
        binary="",
        host="localhost",
        port="19868",
        post_subdomain="topics2",
        autostart=False,  # already started above
    ),
    Service(
        name="extract-categories",
        binary="",
        host="wlo.yovisto.com/services",
        port=None,
        post_subdomain="extract",
        autostart=False,  # not directly integrated in the kidra
    ),
]


def main():
    # listen to requests from any incoming IP address
    cherrypy.server.socket_host = "0.0.0.0"
    webservice = KidraService(SERVICES)

    # override post function for extract-categories,
    # because it expects a string, not a JSON object
    service = SERVICES[3]
    def fun(data: dict) -> dict:
        return requests.post(
            service.api_address,
            # encode as UTF-8 to prevent umlauts etc. causing issues
            data=data["text"].encode("utf-8")
        ).json()

    webservice.post_request_funs["extract-categories"] = fun

    # start the web service
    cherrypy.quickstart(webservice)


if __name__ == "__main__":
    main()
