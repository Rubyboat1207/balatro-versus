# ![logo](resources/1x/versus-logo.png)

## Balatro Versus Mod

The balatro versus mod is a 2+ player experience (in early development) in which players compete to see how high they can score each blind. When winning a blind compared to all other players, they recieve a reward.

### Changes

- All blinds now must now have all hands played, even after matching the score requirement.
- When play started, all connected games will begin at once and with the same seed
- Multiplayer Tab added in settings
- Highest opponent score shown on sidebar
- Highest scoring player gets a reward
  - Money
  - Perishable Joker
  - Random Consumable Card

### Planned Changes (In no particular order)

- New multiplayer focused jokers & Consumables
- Notifications to show winners/losers
- Extra UI features
- A P2P mode
- Server UI
- Centralized servers with lobbies (instead of/in addition to dedicated servers)

## Installation

This mod requires [lovely injector](https://github.com/ethangreen-dev/lovely-injector), as of writing, it is installed by downloading the latest release or artifact from actions and placing version.dll next to the exe.


### Installation Method 1 (Recommended)

1. Install git or git for windows

2. navigate to the mods directory in the command line. (windows: `%AppData%/Balatro/Mods`, mac: `/Users/$USER/Library/Application Support/Balatro/Mods`) 

3. enter the following in the command line

```
git clone https://github.com/Rubyboat1207/balatro-versus.git
```

Whenever you need to update the mod, simply run the following in the mod's folder

```
git pull
```

### Installation Method 2 (Easiest)

1. Navigate to the mods directory. (windows: `%AppData%/Balatro/Mods`, mac: `/Users/$USER/Library/Application Support/Balatro/Mods`)

2. Click the green code button at the top of the page, and then click `Download Zip`

3. Extract the contents of the file to ``Mods/balatro-versus``

> [!WARNING]
> The Folder must be named "balatro-versus" (case sensitive)

## Usage

This mod uses a client-server architecture, so to play with your friends, you'll need to run your own dedicated server. Get the latest artifact at [this repo](https://github.com/Rubyboat1207/balatro-vs-server)
