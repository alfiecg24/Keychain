# Keychain
## A command line tool to fetch iOS firmware keys


## Usage
Keychain is a command line tool that enables you to easily fetch firmware keys for any iOS version and device, as well as getting the URL to an IPSW for any device and version.

It's as simple as this:
`keychain keys -d iPhone12,1 -s 14.0`

If there's keys available for the version/device combination you give, you can choose between the different images to get the correct keys.

You can also fetch the URL for any IPSW like this:
`keychain url -d iPhone12,1 -s 14.0`

The URL will be returned to you for you to go and download from.

## Dependencies
Keychain depends on tihmstar's [partialZipBrowser]("https://github.com/tihmstar/partialZipBrowser").

Please ensure the binary is inside `/usr/local/bin` so that keychain can find it.

## To-do
* Integrate partial zip browser source to remove dependency
* Change this program to a Swift package, and then use that for both a command line tool and a macOS app