class_name TableLayout
extends RefCounted
const TILE = Vector3(0.52, 0.34, 0.74)
const SURFACE_Y = 0.123
const TILE_Y = SURFACE_Y + TILE.y / 2 + 0.008
const STACK_PITCH = 0.35
const RIVER_SCALE = 0.9
const HAND_PITCH = 0.56

static func from_seat(seat: int, lateral: float, depth: float, height: float = TILE_Y) -> Vector3:
	return Vector3(lateral,height,depth).rotated(Vector3.UP,seat*PI/2)

static func river(seat: int,index: int) -> Vector3:
	var wide=index>=18
	var slot=index-18 if wide else index
	var columns=10 if wide else 6
	var row=(3 if wide else 0)+slot/columns
	return from_seat(seat,(slot%columns-2.5)*0.5,(1.50 if seat%2==0 else 2.12)+row*0.69,SURFACE_Y+TILE.y*RIVER_SCALE/2+0.008)

static func wall(index: int, slots: Array = []) -> Vector3:
	var side=index/36
	var partner=index+1 if index%2==0 else index-1
	var layer=1 if index%2==0 and (slots.is_empty() or partner in slots) else 0
	return Vector3((8.5-(index%36)/2)*0.56,TILE_Y+layer*STACK_PITCH,5.0 if side%2==0 else 5.85).rotated(Vector3.UP,-side*PI/2)

static func hand(seat: int,index: int,count: int,drawn: int=-1,standing: bool=true) -> Vector3:
	var height=SURFACE_Y+(TILE.z/2 if standing else TILE.y/2)+0.008
	return from_seat(seat,(index-(count-1)/2.0)*HAND_PITCH+(0.19 if index==drawn else 0),6.92 if seat%2==0 else 7.52,height)

static func meld(seat: int,offset: float,raised: bool=false) -> Vector3:
	return from_seat(seat,(-5.6 if seat==0 else -4.72)+offset,5.88 if seat%2==0 else 6.73,TILE_Y+(STACK_PITCH if raised else 0))

static func flower(seat: int,index: int) -> Vector3:
	# The outer corner lane clears the neighbouring seat's first meld, even
	# with all eight flowers. Near-edge flowers use two shallow rows so the
	# player's screen-space hand never covers them, including the left seat.
	var height=SURFACE_Y+TILE.y*0.65/2+0.008
	if seat==0:
		return from_seat(seat,6.18+(index%4)*0.42,5.55+(index/4)*0.51,height)
	if seat==3:
		return from_seat(seat,5.55+(index/4)*0.38,6.18+(index%4)*0.51,height)
	return from_seat(seat,6.65+(index%2)*0.37,5.55+(index/2)*0.51,SURFACE_Y+TILE.y*0.65/2+0.008)
