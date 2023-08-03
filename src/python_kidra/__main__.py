import cherrypy
from python_kidra.webservice import Service, KidraService

# the collection of all services to be collected in the kidra
SERVICES: set[Service] = {
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
        autostart=False,
    ),
}


def main():
    # listen to requests from any incoming IP address
    cherrypy.server.socket_host = "0.0.0.0"
    webservice = KidraService(SERVICES)
    cherrypy.quickstart(webservice)


if __name__ == "__main__":
    main()
