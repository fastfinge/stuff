Title: YubiKey And Screen Readers
Published: 2026-05-13
Lead: I couldn't find any real information about how Yubikeys work with screen readers. So I decided to publish some.
Tags:
- articles
Fedi: https://fed.interfree.ca/notes/am83nnbz61vvzt9m
---

Before we get into it, we should start with the basics for those who are unaware. What is a Yubikey, and why do you want one?

Well, a Yubikey is a security device that can keep your accounts secure similar to how two factor does, but without needing to enter long numbers or scan QR codes. It's a small hardware device, about as long as a thumb drive, but thinner.  You can get versions that connect via USB-A, USB-C, and/or NFC. I might go as far as saying that it's the most accessible way you can secure your online accounts. No weird apps with revolving codes, no text messages that time out before you can type in the code they want, no having a passcode but it's on the wrong device so you have to scan a QR code. You just connect your Yubikey, touch it, and go! It'll work with your Apple, Google, Amazon, Microsoft, and other accounts. If you have your key, you can log in on any device just by touching the key when prompted.

The device itself has an obvious, easy to find indentation for where you need to touch it with your finger. If you can connect and disconnect USB-C devices independently, Yubikey will work for you. The setup is also fully configurable, at least on Windows and IOS. Just get the Yubico Authenticator app.  

As with anything blind folks do online, however, there are a few weird little things you should know. First, on Windows, the app you need is the Yubico Authenticator. There is another app, called the Yubikey Manager, that is completely inaccessible. It's being phased out, and is no longer supported, but it's easy to grab and install the wrong app. 

Second, when you plug Yubikey into your phone, you need to toggle off a setting called TOTP. The first time you open the app, it should prompt you. But if you miss it, you can toggle it easily in the settings. When this setting is turned on, Yubikey shows up as a keyboard; plugging it in will cause your on-screen keyboard to disappear, and your Braille display keys to stop working. But once you toggle it off, it will stay off. 

Third, on Windows, when you're setting up a new passcode, it's not obvious that it wants to save it to your device by default. To save it to your Yubikey, you have to tab to the list of devices, and switch to "security key". Once you do, you'll be able to use the passcode on any device you can connect the Yubikey to.

The last little niggle: when you're using your Yubikey on Windows with SSH Keys, or any other app that needs to authenticate from the command line, the windows security dialogue informing you to touch the Yubikey doesn't always get focused by your screen reader. Just like those UAC dialogues you have to say "yes" to when you install software, sometimes you have to alt-tab to find the window.  

Other than that, my Yubikey experience is far better than any other two-factor or passkey flow, and I strongly recommend that more blind folks investigate it.