import argparse


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--help", action="help")
    parser.add_argument("-h", "--host", required=True)
    parser.add_argument("-p", "--port", type=int, default=3389)
    parser.add_argument("-u", "--username")
    parser.add_argument("-d", "--domain")
    parser.add_argument("-o", "--output")
    parser.add_argument("--gateway")
    parser.add_argument("--remoteapp")
    parser.add_argument("--app-name")
    parser.add_argument("--app-args")
    parser.add_argument("--app-file")
    parser.add_argument("--app-dir")
    parser.add_argument("--set", action="append", default=[])
    parser.add_argument("--print", action="store_true")
    args = parser.parse_args()

    address = args.host
    if args.port != 3389:
        address += ":" + str(args.port)

    settings = {
        "full address": "s:" + address,
        "drivestoredirect": "s:*",
        "redirectclipboard": "i:1",
        "redirectprinters": "i:1",
        "redirectsmartcards": "i:1",
        "usbdevicestoredirect": "s:*",
        "camerastoredirect": "s:*",
        "audiomode": "i:0",
        "audiocapturemode": "i:1",
        "screen mode id": "i:2",
        "use multimon": "i:1",
        "dynamic resolution": "i:1",
        "smart sizing": "i:1",
        "autoreconnection enabled": "i:1",
        "connection type": "i:7",
        "networkautodetect": "i:1",
        "bandwidthautodetect": "i:1",
        "authentication level": "i:2",
        "enablecredsspsupport": "i:1",
    }

    if args.username:
        user = args.username
        if args.domain:
            user = args.domain + "\\" + user
        settings["username"] = "s:" + user

    if args.gateway:
        settings["gatewayhostname"] = "s:" + args.gateway
        settings["gatewayusagemethod"] = "i:1"
        settings["gatewaycredentialssource"] = "i:4"
        settings["gatewayprofileusagemethod"] = "i:1"
        settings["promptcredentialonce"] = "i:1"

    if args.remoteapp:
        settings["remoteapplicationmode"] = "i:1"
        settings["remoteapplicationprogram"] = "s:" + args.remoteapp
        settings["remoteapplicationname"] = "s:" + (args.app_name or args.remoteapp.strip("|"))
        if args.app_args:
            settings["remoteapplicationcmdline"] = "s:" + args.app_args
        if args.app_file:
            settings["remoteapplicationfile"] = "s:" + args.app_file
        if args.app_dir:
            settings["shell working directory"] = "s:" + args.app_dir
        if not args.remoteapp.startswith("||"):
            settings["disableremoteappcapscheck"] = "i:1"

    for s in args.set:
        key, val = s.split(":", 1)
        settings[key] = val

    rdp = ""
    for key, val in settings.items():
        rdp += key + ":" + val + "\n"

    if args.print:
        print(rdp)
    else:
        filename = args.output or args.host + ".rdp"
        with open(filename, "w", encoding="utf-16", newline="\r\n") as f:
            f.write(rdp)
        print("Saved: {}".format(filename))


if __name__ == "__main__":
    main()