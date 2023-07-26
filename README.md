# Cannon Control Pseudocode

Project Outline: Goal is to write a lua program for a CC:Tweaked computer to execute such that I enter in an xyz coordinate and the computer pivots a connected Create: Big Cannons cannon to aim at that position, accounting for cannon size, powder load, and gravity.


## Control Requirements
Computer must be connected to the cannon mount via a peripheral and also connected to a clutch and gearshift for both the cannon mount and yaw controller. Computer must be given the cannon's current position in the world and the direction the cannon is facing at rest.

## Control Procedure
User enters the required info: 
- Cannon Postion, Direction, and Size
- Powder load
- XYZ coordinate of target

(some info may be already be saved by the computer, such as the cannon position and direction, and size)

Then the computer will change the yaw of the cannon until it is facing the XZ coordinate of the target.

The computer then calculates the required pitch of cannon and tilts it until it is in the correct position.

The user must then hit the firing button on the cannon to fire.

Autonomous firing is possible, however it could pose a security risk if an unauthorized user gains access to the computer running the program.

## Development Procedure
### Preliminary Testing
Phase 1 of development will be conducting manual firing tests to collect data needed to create the control algorithms. 

### Range Calculator
Phase 2 of development will be making an algorithm that calculates the range of a cannon based on its size and powder load.  

### Dead Ahead Calculator
Phase 3 of development will be making an algorithm that calculates the needed tilt of a cannon to hit a target straight ahead.  

### Firing Program
Phase 4 of development will be using the Dead Ahead Calculator after turning the cannon to the correct yaw to aim at a target position within the range obtained from the Range Calculator.  
