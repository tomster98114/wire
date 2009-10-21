if (not EmuFox) then
	include('shared.lua')
end

ENT.Spawnable      = false
ENT.AdminSpawnable = false
ENT.RenderGroup    = RENDERGROUP_BOTH


function ENT:Initialize()
	self.Memory1 = {}
	self.Memory2 = {}
	for i = 0, 2047 do
		self.Memory1[i] = 0
	end

	//Caching control:
	//[2020] - Force cache refresh
	//[2021] - Cached blocks size (up to 28, 0 if disabled)
	//Hardware image control:
	//[2019] - Clear viewport defined by 2031-2034
	//[2022] - Screen ratio (read only)
	//[2023] - Hardware scale
	//[2024] - Rotation (0 - 0*, 1 - 90*, 2 - 180*, 3 - 270*)
	//[2025] - Brightness White
	//[2026] - Brightness B
	//[2027] - Brightness G
	//[2028] - Brightness R
	//[2029] - Vertical scale (1)
	//[2030] - Horizontal scale (1)
	//
	//Shifting control:
	//[2031] - Low shift column
	//[2032] - High shift column
	//[2033] - Low shift row
	//[2034] - High shift row
	//
	//Character output control:
	//[2035] - Charset, always 0
	//[2036] - Brightness (additive)
	//
	//Control registers:
	//[2037] - Shift cells (number of cells, >0 right, <0 left)
	//[2038] - Shift rows (number of rows, >0 shift up, <0 shift down)
	//[2039] - Hardware Clear Row (Writing clears row)
	//[2040] - Hardware Clear Column (Writing clears column)
	//[2041] - Hardware Clear Screen
	//[2042] - Hardware Background Color (000)
	//
	//Cursor control:
	//[2043] - Cursor Blink Rate (0.50)
	//[2044] - Cursor Size (0.25)
	//[2045] - Cursor Address
	//[2046] - Cursor Enabled
	//
	//[2047] - Clk

	self.Memory1[2022] = 3/4
	self.Memory1[2023] = 0
	self.Memory1[2024] = 0
	self.Memory1[2025] = 1
	self.Memory1[2026] = 1
	self.Memory1[2027] = 1
	self.Memory1[2028] = 1
	self.Memory1[2029] = 1
	self.Memory1[2030] = 1
	self.Memory1[2031] = 0
	self.Memory1[2032] = 29
	self.Memory1[2033] = 0
	self.Memory1[2034] = 17
	self.Memory1[2035] = 0
	self.Memory1[2036] = 0

	self.Memory1[2042] = 0
	self.Memory1[2043] = 0.5
	self.Memory1[2044] = 0.25
	self.Memory1[2045] = 0
	self.Memory1[2046] = 0

	for i = 0, 2047 do
		self.Memory2[i] = self.Memory1[i]
	end

	self.LastClk = false

	self.PrevTime = CurTime()
	self.IntTimer = 0

	self.NeedRefresh = true
	self.Flash = false
	self.FrameNeedsFlash = false

	self.FramesSinceRedraw = 0
	self.NewClk = true

	WireGPU_NeedRenderTarget(self:EntIndex())
end

function ENT:OnRemove()
	WireGPU_ReturnRenderTarget(self:EntIndex())
end

local function calcoffset(offset, Address)
	offset = -100 - offset+Address
	if offset >= 1048576 then offset = offset - 1048576 end
	return offset
end

usermessage.Hook("hispeed_datastream", function(um)
	local ent = ents.GetByIndex(um:ReadShort())

	if not ValidEntity(ent) then return end
	if not ent.Memory1 then return end
	if not ent.Memory2 then return end

	local Address = 0
	while true do
		local value = um:ReadFloat()
		if value < -100 then
			Address = calcoffset(value, Address)
		elseif value == -100 then
			break
		else
			ent:WriteCell(Address, value)
			Address = Address + 1
		end
	end
end)

function ENT:ReadCell(Address,value)
	if Address < 0 then return nil end
	if Address >= 2048 then return nil end

	return self.Memory2[Address]
end

function ENT:WriteCell(Address,value)
	if Address < 0 then return false end
	if Address >= 2048 then return false end

	if (Address == 2047) then self.NewClk = value ~= 0 end

	if (self.NewClk) then
		self.Memory1[Address] = value //Vis mem
		self.NeedRefresh = true
	end
	self.Memory2[Address] = value //Invis mem

	//2038 - Shift rows (number of rows, >0 shift down, <0 shift up)
	//2039 - Hardware Clear Row (Writing clears row)
	//2040 - Hardware Clear Column (Writing clears column)
	//2041 - Hardware Clear Screen

	if (Address == 2019) then
		local low = math.floor(math.Clamp(self.Memory1[2033],0,17))
		local high = math.floor(math.Clamp(self.Memory1[2034],0,17))
		local lowc = math.floor(math.Clamp(self.Memory1[2031],0,29))
		local highc = math.floor(math.Clamp(self.Memory1[2032],0,29))
		for j = low, high do
			for i = 2*lowc, 2*highc+1 do
				self.Memory1[60*j+i] = 0
				self.Memory2[60*j+i] = 0
			end
		end
		self.NeedRefresh = true
	end
	if (Address == 2037) then
		local delta = math.abs(value)
		local low = math.floor(math.Clamp(self.Memory1[2033],0,17))
		local high = math.floor(math.Clamp(self.Memory1[2034],0,17))
		local lowc = math.floor(math.Clamp(self.Memory1[2031],0,29))
		local highc = math.floor(math.Clamp(self.Memory1[2032],0,29))
		if (value > 0) then
			for j = low,high do
				for i = highc,lowc+delta,-1 do
					if (self.NewClk) then
						self.Memory1[j*60+i*2] = self.Memory1[j*60+(i-delta)*2]
						self.Memory1[j*60+i*2+1] = self.Memory1[j*60+(i-delta)*2+1]
					end
					self.Memory2[j*60+i*2] = self.Memory2[j*60+(i-delta)*2]
					self.Memory2[j*60+i*2+1] = self.Memory2[j*60+(i-delta)*2+1]
				end
			end
			for j = low,high do
				for i = lowc, lowc+delta-1 do
					if (self.NewClk) then
						self.Memory1[j*60+i*2] = 0
						self.Memory1[j*60+i*2+1] = 0
					end
					self.Memory2[j*60+i*2] = 0
					self.Memory2[j*60+i*2+1] = 0
				end
			end
		else
			for j = low,high do
				for i = lowc,highc-delta do
					if (self.NewClk) then
						self.Memory1[j*60+i*2] = self.Memory1[j*60+i*2+delta*2]
						self.Memory1[j*60+i*2+1] = self.Memory1[j*60+i*2+1+delta*2]
					end
					self.Memory2[j*60+i*2] = self.Memory2[j*60+i*2+delta*2]
					self.Memory2[j*60+i*2+1] = self.Memory2[j*60+i*2+1+delta*2]
				end
			end
			for j = low,high do
				for i = highc-delta+1,highc do
					if (self.NewClk) then
						self.Memory1[j*60+i*2] = 0
						self.Memory1[j*60+i*2+1] = 0
					end
					self.Memory2[j*60+i*2] = 0
					self.Memory2[j*60+i*2+1] = 0
				end
			end
		end
	end
	if (Address == 2038) then
		local delta = math.abs(value)
		local low = math.floor(math.Clamp(self.Memory1[2033],0,17))
		local high = math.floor(math.Clamp(self.Memory1[2034],0,17))
		local lowc = math.floor(math.Clamp(self.Memory1[2031],0,29))
		local highc = math.floor(math.Clamp(self.Memory1[2032],0,29))
		if (value > 0) then
			for j = low, high-delta do
				for i = 2*lowc,2*highc+1  do
					if (self.NewClk) then
						self.Memory1[j*60+i] = self.Memory1[(j+delta)*60+i]
					end
					self.Memory2[j*60+i] = self.Memory2[(j+delta)*60+i]
				end
			end
			for j = high-delta+1,high do
				for i = 2*lowc, 2*highc+1 do
					if (self.NewClk) then
						self.Memory1[j*60+i] = 0
					end
					self.Memory2[j*60+i] = 0
				end
			end
		else
			for j = high,low+delta,-1 do
				for i = 2*lowc, 2*highc+1 do
					if (self.NewClk) then
						self.Memory1[j*60+i] = self.Memory1[(j-delta)*60+i]
					end
					self.Memory2[j*60+i] = self.Memory2[(j-delta)*60+i]
				end
			end
			for j = low,low+delta-1 do
				for i = 2*lowc, 2*highc+1 do
					if (self.NewClk) then
						self.Memory1[j*60+i] = 0
					end
					self.Memory2[j*60+i] = 0
				end
			end
		end
	end
	if (Address == 2039) then
		for i = 0, 59 do
			self.Memory1[value*60+i] = 0
			self.Memory2[value*60+i] = 0
		end
		self.NeedRefresh = true
	end
	if (Address == 2040) then
		for i = 0, 17 do
			self.Memory1[i*60+value] = 0
			self.Memory2[i*60+value] = 0
		end
		self.NeedRefresh = true
	end
	if (Address == 2041) then
		for i = 0, 18*30*2-1 do
			self.Memory1[i] = 0
			self.Memory2[i] = 0
		end
		self.NeedRefresh = true
	end

	if (self.LastClk ~= self.NewClk) then
		self.LastClk = self.NewClk
		self.Memory1 = table.Copy(self.Memory2) //swap the memory if clock changes

		self.NeedRefresh = true
	end
	return true
end

function ENT:DrawGraphicsChar(c,x,y,w,h,r,g,b)
	surface.SetDrawColor(r,g,b,255)
	surface.SetTexture(0)

	if (c == 128) then
		vertex = {}

		//Generate vertex data
		vertex[1] = {}
		vertex[1]["x"] = x
		vertex[1]["y"] = y+h

		vertex[2] = {}
		vertex[2]["x"] = x+w
		vertex[2]["y"] = y+h

		vertex[3] = {}
		vertex[3]["x"] = x+w
		vertex[3]["y"] = y
		surface.DrawPoly(vertex)
	end

	if (c == 129) then
		vertex = {}

		//Generate vertex data
		vertex[1] = {}
		vertex[1]["x"] = x
		vertex[1]["y"] = y+h

		vertex[2] = {}
		vertex[2]["x"] = x
		vertex[2]["y"] = y

		vertex[3] = {}
		vertex[3]["x"] = x+w
		vertex[3]["y"] = y+h
		surface.DrawPoly(vertex)
	end

	if (c == 130) then
		vertex = {}

		//Generate vertex data
		vertex[1] = {}
		vertex[1]["x"] = x
		vertex[1]["y"] = y+h

		vertex[2] = {}
		vertex[2]["x"] = x+w
		vertex[2]["y"] = y

		vertex[3] = {}
		vertex[3]["x"] = x
		vertex[3]["y"] = y
		surface.DrawPoly(vertex)
	end

	if (c == 131) then
		vertex = {}

		//Generate vertex data
		vertex[1] = {}
		vertex[1]["x"] = x
		vertex[1]["y"] = y

		vertex[2] = {}
		vertex[2]["x"] = x+w
		vertex[2]["y"] = y

		vertex[3] = {}
		vertex[3]["x"] = x+w
		vertex[3]["y"] = y+h
		surface.DrawPoly(vertex)
	end
end

function ENT:Draw()
	self.Entity:DrawModel()

	local DeltaTime = CurTime()-(self.PrevTime or CurTime())
	self.PrevTime = (self.PrevTime or CurTime())+DeltaTime
	self.IntTimer = self.IntTimer + DeltaTime

	self.RTTexture = WireGPU_GetMyRenderTarget(self:EntIndex())

	local NewRT = self.RTTexture
	local OldRT = render.GetRenderTarget()

	local OldTex = WireGPU_matScreen:GetMaterialTexture("$basetexture")
	WireGPU_matScreen:SetMaterialTexture("$basetexture",self.RTTexture)

	self.FramesSinceRedraw = self.FramesSinceRedraw + 1

	if (self.NeedRefresh == true) then
		self.FramesSinceRedraw = 0
		self.NeedRefresh = false
		self.FrameNeedsFlash = false

		if (self.Memory1[2046] >= 1) then self.FrameNeedsFlash = true end

		local oldw = ScrW()
		local oldh = ScrH()

		render.SetRenderTarget(NewRT)
		render.SetViewPort(0,0,512,512)
		cam.Start2D()
			//Draw terminal here
			//W/H = 16
			local szx = 512/31
			local szy = 512/19

			local ch = self.Memory1[2042]

			local hb = 28*math.fmod(ch,10)
			local hg = 28*math.fmod(math.floor(ch / 10),10)
			local hr = 28*math.fmod(math.floor(ch / 100),10)
			surface.SetDrawColor(hr,hg,hb,255)
			surface.DrawRect(0,0,512,512)

			for ty = 0, 17 do
				for tx = 0, 29 do
					local a = tx + ty*30
					local c1 = self.Memory1[2*a]
					local c2 = self.Memory1[2*a+1]

					local cback = math.floor(c2 / 1000)
					local cfrnt = c2 - math.floor(c2 / 1000)*1000

					local fb = math.Clamp(28*math.fmod(cfrnt,10) + self.Memory1[2036],0,255)
					local fg = math.Clamp(28*math.fmod(math.floor(cfrnt / 10),10) + self.Memory1[2036],0,255)
					local fr = math.Clamp(28*math.fmod(math.floor(cfrnt / 100),10) + self.Memory1[2036],0,255)
					local bb = math.Clamp(28*math.fmod(cback,10) + self.Memory1[2036],0,255)
					local bg = math.Clamp(28*math.fmod(math.floor(cback / 10),10) + self.Memory1[2036],0,255)
					local br = math.Clamp(28*math.fmod(math.floor(cback / 100),10) + self.Memory1[2036],0,255)

					if (self.Flash == true) && (cback > 999) then
						fb,bb = bb,fb
						fg,bg = bg,fg
						fr,br = br,fr
					end

					if (cback > 999) then
						self.FrameNeedsFlash = true
					end

					if (c1 > 255) then c1 = 0 end
					if (c1 < 0) then c1 = 0 end

					if (cback ~= 0) then
						surface.SetDrawColor(br,bg,bb,255)
						surface.DrawRect(tx*szx+szx/2,ty*szy+szy/2,szx*1.2,szy*1.2)
					else
						surface.SetDrawColor(hr,hg,hb,255)
						surface.DrawRect(tx*szx+szx/2,ty*szy+szy/2,szx*1.2,szy*1.2)
					end

					if (c1 ~= 0) && (cfrnt ~= 0) then
						if (c1 <= 127) then
							draw.DrawText(string.char(c1),"WireGPU_ConsoleFont",
							tx*szx+szx/8+szx/2,ty*szy+szy/4+szy/2,
							Color(math.Clamp(fr*self.Memory1[2028]*self.Memory1[2025],0,255),
							      math.Clamp(fg*self.Memory1[2027]*self.Memory1[2025],0,255),
							      math.Clamp(fb*self.Memory1[2026]*self.Memory1[2025],0,255),
							      255),0)
						else
							self:DrawGraphicsChar(c1,tx*szx+szx/2,ty*szy+szy/2,szx,szy,
								math.Clamp(fr*self.Memory1[2028]*self.Memory1[2025],0,255),
								math.Clamp(fg*self.Memory1[2027]*self.Memory1[2025],0,255),
								math.Clamp(fb*self.Memory1[2026]*self.Memory1[2025],0,255))
						end
					end
				end
			end

			if (self.Memory1[2045] > 1080) then self.Memory1[2045] = 1080 end
			if (self.Memory1[2045] < 0) then self.Memory1[2045] = 0 end
			if (self.Memory1[2044] > 1) then self.Memory1[2044] = 1 end
			if (self.Memory1[2044] < 0) then self.Memory1[2044] = 0 end

			if (self.Memory1[2046] >= 1) then
				if (self.Flash == true) then
					local a = math.floor(self.Memory1[2045] / 2)

					local tx = a - math.floor(a / 30)*30
					local ty = math.floor(a / 30)

					local c = self.Memory1[2*a+1]
					local cback = 999-math.floor(c / 1000)
					local bb = 28*math.fmod(cback,10)
					local bg = 28*math.fmod(math.floor(cback / 10),10)
					local br = 28*math.fmod(math.floor(cback / 100),10)

					surface.SetDrawColor(
						math.Clamp(br*self.Memory1[2028]*self.Memory1[2025],0,255),
						math.Clamp(bg*self.Memory1[2027]*self.Memory1[2025],0,255),
						math.Clamp(bb*self.Memory1[2026]*self.Memory1[2025],0,255),
						255
					)
					surface.DrawRect(
						tx*szx+szx/2,
						ty*szy+szy/2+szy*1.2*(1-self.Memory1[2044]),
						szx*1.2,
						szy*1.2*self.Memory1[2044]
					)
				end
			end
	 	cam.End2D()
	 	render.SetViewPort(0,0,oldw,oldh)
	 	render.SetRenderTarget(OldRT)
	end

	if (self.FrameNeedsFlash == true) then
		if (self.IntTimer < self.Memory1[2043]) then
			if (self.Flash == false) then
				self.NeedRefresh = true
			end
			self.Flash = true
		end

		if (self.IntTimer >= self.Memory1[2043]) then
			if (self.Flash == true) then
				self.NeedRefresh = true
			end
			self.Flash = false
		end

		if (self.IntTimer >= self.Memory1[2043]*2) then
			self.IntTimer = 0
		end
	end

	if (EmuFox) then
		return
	end

	local model = self.Entity:GetModel()
	local OF, OU, OR, Res, RatioX, Rot90
	if (WireGPU_Monitors[model]) && (WireGPU_Monitors[model].OF) then
		OF = WireGPU_Monitors[model].OF
		OU = WireGPU_Monitors[model].OU
		OR = WireGPU_Monitors[model].OR
		Res = WireGPU_Monitors[model].RS
		RatioX = WireGPU_Monitors[model].RatioX
		Rot90 = WireGPU_Monitors[model].rot90
	else
		OF = 0
		OU = 0
		OR = 0
		Res = 1
		RatioX = 1
	end

	local ang = self.Entity:GetAngles()
	local rot = Vector(-90,90,0)
	if Rot90 then
		rot = Angle(0,90,0)
	end

	ang:RotateAroundAxis(ang:Right(),   rot.x)
	ang:RotateAroundAxis(ang:Up(),      rot.y)
	ang:RotateAroundAxis(ang:Forward(), rot.z)

	local pos = self.Entity:GetPos()+(self.Entity:GetForward()*OF)+(self.Entity:GetUp()*OU)+(self.Entity:GetRight()*OR)

	cam.Start3D2D(pos,ang,Res)
		local w = 512*math.Clamp(self.Memory1[2030],0,1)
		local h = 512*math.Clamp(self.Memory1[2029],0,1)
		local x = -w/2
		local y = -h/2

		surface.SetDrawColor(0,0,0,255)
		surface.DrawRect(-256,-256,512/RatioX,512)

		surface.SetDrawColor(255,255,255,255)
		surface.SetTexture(WireGPU_texScreen)
		WireGPU_DrawScreen(x,y,w/RatioX,h,self.Memory1[2024],self.Memory1[2023])
	cam.End3D2D()

	WireGPU_matScreen:SetMaterialTexture("$basetexture",OldTex)
	Wire_Render(self.Entity)
end

function ENT:IsTranslucent()
	return true
end