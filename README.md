# sj_safes

A FiveM resource that adds functional, crackable, and placeable safes to your server.

## Features

- Place safes anywhere in the world
- Combination lock system
- Safe cracking minigame
- Multiple safe types with different storage capacities
- Admin management system
- Persistent storage

## To-Do

- [ ] Additional security options:
  - [ ] Keypad/code entry system
  - [ ] Key-based locks
  - [ ] Electronic security features
- [ ] More safe types and models
- [ ] Safe sharing/permissions system
- [ ] Advanced anti-theft features
- [ ] Timeout based safe access after successful entry of code/combination (so users don't have to enter code over and over if it's their own safe)

## Dependencies

- QBX Core
- ox_lib
- ox_inventory
- ox_target

## Installation

1. Download the latest release
2. Place the `sj_safes` folder in your server's resources directory
3. Add `ensure sj_safes` to your server.cfg
4. Add the following items to your ox_inventory/data/items.lua:
```lua
['small_safe'] = {
    label = 'Small Safe',
    weight = 50000,
    stack = false,
    description = 'A small safe for storing valuables'
},
['large_safe'] = {
    label = 'Large Safe',
    weight = 100000,
    stack = false,
    description = 'A large safe for storing valuables'
}
```
5. Add the following ace permission for admin access:
```
add_ace group.admin sj_safes.admin allow
```

## Usage

### Player Commands
- `/safes` - Admin command to manage placed safes (requires sj_safes.admin ace permission)

### Item Usage
- Use the safe item from your inventory to place it
- Target a placed safe using ox_target to interact
- Enter the correct combination to access the storage

### Admin Features
- View all placed safes
- Remove safes (bypasses empty check)
- See safe ownership and contents

## Configuration

Edit `config.lua` to customize:
- Safe types and capacities
- Maximum safes per player
- Placement restrictions
- UI settings

## License

This resource is licensed under Creative Commons Attribution-NonCommercial 4.0 International License. This means:
- You can freely use and modify this resource
- You must provide attribution/credit
- You cannot sell this resource or include it in any paid/premium content
- You cannot use this resource on a paid/commercial server where this code provides value to the paid service

See the LICENSE file for details.

## Support

For issues and feature requests, please use the GitHub issues page.
