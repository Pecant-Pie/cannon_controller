# Cannon Controller Info

Project Outline: Create a lua program for a CC:Tweaked computer that I can use to enter in an xyz coordinate and have the computer aim a connected Create: Big Cannons cannon at that position, accounting for cannon size, powder load, and gravity.


## Control Requirements
Computer must be able to use redstone to activate and deactivate a clutch and gearshift for the cannon mount and yaw controller each. Computer must be given the cannon's current position in the world and the direction the cannon is facing at rest.

## Control Procedure
User enters the required info to initially set up a cannon: 
- Cannon Postion, Direction, and Length

User enters this information every time before firing:
- Powder load
- XYZ coordinate of target

The computer will then calculate the yaw needed to face the XZ coordinate of the target, and 
the required pitch of cannon to hit the target. It then moves the cannon until it is in the correct position.

The user must then hit the firing button on the cannon to fire, or a separate computer may activate the cannon to fire.

# Development Procedure
## Version 0.0
### Preliminary Testing
Conduct manual firing tests to collect data needed to create the control algorithms.  
```
I conducted this testing and discovered that linear air resistance is present for the projectiles. I searched online
for ways to solve equations with linear air drag and it seemed much more complicated than using a simulated 'try it 
until it works' approach. So I looked at the internal code for the movement of the cannon shots and mimicked that in 
my simulation code for the control program.
```

### Range Calculator
Make an algorithm that calculates the range of a cannon based on its size and powder load.  
```
This was scrapped because the Firing program is fast enough that it can be efficiently used as a range calculator on its own.
```

### Dead Ahead Calculator
Make an algorithm that calculates the needed tilt of a cannon to hit a target straight ahead.  
```
This was the first version of the firing program, and includes my simulation code for the shot trajectories and the code for 
refining the aim guess until a suitable trajectory is found.
```

### Firing Program
Use the Dead Ahead Calculator after turning the cannon to the correct yaw to aim at a target position 
within the range obtained from the Range Calculator.  
```
This does not use a range calculator but instead returns 'nil' if a suitable trajectory was not found, which would result from the
target being out of range. Involves three main functions: getHorizAngle() for getting the yaw, refineShot() for getting the pitch,
and aimCannon() for actually moving the cannon into position.
```

## Version 1.0
### Enhanced Control
Create a helpful user-interface for aiming the cannon at a relative position, to replace the current
hard-coded approach within the Firing Program.

### Automated Control
Wrap the existing firing program within a constantly 'listening' program that can receive its
control instructions from another computer on a wired or wireless network. This will allow for the coordination of multiple cannons
to fire at the same or different positions at once.

### Automated Reload
Create a generic system for reloading the cannon after each shot and notifying the user when the 
cannon is ready to fire again.

### Secure Firing
Create a program to be run by the cannon reloader that listens to the network and fires the cannon when it
receives a specified passcode.
