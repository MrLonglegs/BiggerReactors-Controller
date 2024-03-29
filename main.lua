--Initialize Reactor and Turbine lists
reactors = {}
turbines = {}

--Initialize default config values

--Reactor
local foundReactors = 0
local reactorTargetBufferMin = 30
local reactorTargetBufferMax = 70

--Turbine
local foundTurbines = 0
local targetRPM = 1820
local maxRPM = 2200
local turbineTargetBufferMin = 70
local turbineTargetBufferMax = 99
local maxFlowRate = 13000


--Program
local loopTime = 0.5 --Time for each loop of main
local running = true --Variable to determine whether the control program should run

--Turns all reactors off. Duh...
function AllReactorsOff()
    for _, reactor in pairs(reactors) do
        reactor.setActive(false)
    end
end

--Turns all reactors on. Duh...
function AllReactorsOn()
    for _, reactor in pairs(reactors) do
        reactor.setActive(true)
    end
end

--Turns all turbines on. Duh...
function AllTurbinesOn()
    for _, turbine in pairs(turbines) do
        turbine.setActive(true)
    end
end

--Turns all turbines off. Duh...
function AllTurbinesOff()
    for _, turbine in pairs(turbines) do
        turbine.setActive(false)
    end
end

--Initialize static reactor values, which may vary from reactor to reactor.
function InitializeReactorValues()
    for _, reactor in pairs(reactors) do
        if reactor.coolantTank() == nil and reactor.battery() ~= nil then
            reactor.maxBuffer = reactorTargetBufferMax / 100 * reactor.battery().capacity()
            reactor.minBuffer = reactorTargetBufferMin / 100 * reactor.battery().capacity()
            reactor.storedThisTick = reactor.battery().stored()
            reactor.reactorType = "passive"
        else if reactor.coolantTank() ~= nil and reactor.battery() == nil then
            reactor.maxBuffer = reactorTargetBufferMax / 100 * reactor.coolantTank().capacity()
            reactor.minBuffer = reactorTargetBufferMin / 100 * reactor.coolantTank().capacity()
            reactor.storedThisTick = reactor.coolantTank().hotFluidAmount()
            reactor.reactorType = "active"
        end
        end
    end
end

--Initialize static turbine values, which may vary from turbine to turbine.
function InitializeTurbineValues()
    for _, turbine in pairs(turbines) do
        turbine.maxBuffer = turbineTargetBufferMax / 100 * turbine.battery().capacity()
        turbine.minBuffer = turbineTargetBufferMin / 100 * turbine.battery().capacity()
        turbine.storedThisTick = turbine.battery().stored()
    end
end

--Set all control rods of specific reactor.
local function setRods(level, reactor)
    level = math.max(level, 0)
    level = math.min(level, 100)
    reactor.setAllControlRodLevels(level)
end

--Adjust the control rods according to need.
function AdjustControlRods()
    for _, reactor in pairs(reactors) do

        local currentBuffer = reactor.storedThisTick
        local diffb = reactorTargetBufferMax - reactorTargetBufferMin
        reactor.diffRF = diffb / 100 * reactor.capacity
        local diffr = diffb / 100
        local targetBufferT = reactor.bufferLost
        local currentBufferT = reactor.producedLastTick
        local diffBufferT = currentBufferT / targetBufferT
        local targetBuffer = reactor.diffRF / 2 + reactor.minBuffer

        currentBuffer = math.min(currentBuffer, reactor.maxBuffer)
        local equation1 = math.min((currentBuffer - reactor.minBuffer)/reactor.diffRF, 1)
        equation1 = math.max(equation1, 0)

        local rodLevel = reactor.rod
        if (reactor.storedThisTick < reactor.minBuffer) then
            rodLevel = 0
        elseif ((reactor.storedThisTick < reactor.maxBuffer and reactor.storedThisTick > reactor.minBuffer)) then
            equation1 = equation1 * (currentBuffer / targetBuffer) --^ 2
            equation1 = equation1 * diffBufferT --^ 5
            equation1 = equation1 * 100

            rodLevel = equation1
        elseif (reactor.storedThisTick > reactor.maxBuffer) then
            rodLevel = 100
        end
        setRods(rodLevel, reactor)
    end
end

--Adjust the flowrate to achieve set RPM
function AdjustFlowRate()
    for _, turbine in pairs(turbines) do
        if turbine.RPM < targetRPM and turbine.flowRate < maxFlowRate then
            turbine.fluidTank().setNominalFlowRate(turbine.flowRate + turbine.flowRateStep)
        end
        if turbine.RPM > targetRPM then
            turbine.fluidTank().setNominalFlowRate(turbine.flowRate - (turbine.flowRateStep * -1))
        end
        if turbine.storedThisTick < turbine.minBuffer then
            turbine.setCoilEngaged(true)
        end
        if turbine.storedThisTick > turbine.maxBuffer then
            turbine.setCoilEngaged(false)
        end
    end
end

--Update the Stats of the reactors and turbines for further use in the script.
function UpdateStats()
    for _, reactor in pairs(reactors) do
        reactor.storedLastTick = reactor.storedThisTick

        if reactor.reactorType == "passive" then
            reactor.producedLastTick = reactor.battery().producedLastTick()
            reactor.capacity = reactor.battery().capacity()
            reactor.storedThisTick = reactor.battery().stored()
        end
        if reactor.reactorType == "active" then
            reactor.producedLastTick = reactor.coolantTank().transitionedLastTick()
            reactor.capacity = reactor.coolantTank().capacity()
            reactor.storedThisTick = reactor.coolantTank().hotFluidAmount()
        end
        reactor.rod = reactor.getControlRod(0).level()
        reactor.fuelUsage = reactor.fuelTank().burnedLastTick() / 1000
        reactor.waste = reactor.fuelTank().waste()
        reactor.fuelTemp = reactor.fuelTemperature()
        reactor.caseTemp = reactor.casingTemperature()
        reactor.bufferLost = reactor.producedLastTick + reactor.storedLastTick - reactor.storedThisTick
    end
    for _, turbine in pairs(turbines) do
        turbine.storedLastTick = turbine.storedThisTick
        turbine.storedThisTick = turbine.battery().stored()
        turbine.RPM = turbine.rotor().RPM()
        turbine.flowRate = turbine.fluidTank().nominalFlowRate()
        turbine.flowRateStep = (targetRPM - turbine.RPM) * 1
    end
end

--Get CurrentTotalEnergy for further use
function GetCurrentTotalEnergy()
    local currentEnergy = 0
    for _, reactor in pairs(reactors) do
        if reactor.reactorType == "passive" then
            currentEnergy = currentEnergy + reactor.storedThisTick
        end
    end

    for _, turbine in pairs(turbines) do
        currentEnergy = currentEnergy + turbine.storedThisTick
    end

    return currentEnergy
end

-- !! Here starts the main program !!

--Wrap all Monitors, Reactors and Turbines available
reactors = { peripheral.find("BiggerReactors_Reactor") }
turbines = { peripheral.find("BiggerReactors_Turbine") }


--Initizialize machine values
InitializeReactorValues()
InitializeTurbineValues()

--Start all Reactors
AllReactorsOn()
AllTurbinesOn()

--Main working loop
while running do
    UpdateStats()
    AdjustFlowRate()
    AdjustControlRods()

    os.sleep(loopTime)
end
