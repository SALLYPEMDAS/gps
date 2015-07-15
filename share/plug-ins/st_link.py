"""
This plug-in creates buttons on the toolbar to conveniently
flash and debug programs for the STM32F4* boards.

The utility program st-util must be present on the PATH for
the buttons to be made visible. This utility is included in
recent Windows-based versions of GNAT for the arm-eabi targets,
or can be downloaded from https://github.com/texane/stlink and
built. In addition, the utility st-flash is required to be
on the path in order to flash memory as a separate operation.
Note that the USB driver for these utility programs must be
installed in order for them to operate correctly, but this
plug-in is not concerned with that aspect.

"""

import GPS
from modules import Module
import workflows
import workflows.promises as promises


def msg_is(msg):
    GPS.Console("Messages").write(msg + "\n")


def uses_stm32f4(prj):
    """ Search the project to see if it uses the STM32F4 boards
    """
    s = prj.get_attribute_as_string(package="Builder",
                                    attribute="Default_Switches",
                                    index="Ada")
    if "stm32f4" in s:
        return True

    s = prj.get_attribute_as_string(package="Builder",
                                    attribute="Switches",
                                    index="Ada")
    if "stm32f4" in s:
        return True

    s = prj.get_attribute_as_string("runtime", index="Ada")
    if "stm32f4" in s:
        return True

    return False


class BoardLoader(Module):

    # a list of targets
    __targets = ["Flash to Board",
                 "Debug on Board"]
    __buttons = []
    __connection = None

    def __error_exit(self, msg=""):
        """ Emit an error and reset the workflows """
        GPS.Console("Messages").write(msg + " [workflow stopped]")

    def __reset_all(self, manager_delete=True, connection_delete=True):
        """ Reset the workflows """
        if self.__connection is not None and connection_delete:
            self.__connection.get().kill()
            self.__connection = None
        interest = "st-util"
        for i in GPS.Task.list():
            if interest in i.name():
                i.interrupt()

    def __check_task(self, id):
        """ Back up method to check if task exists
        """
        r = False
        interest = ["st-util"][id]
        for i in GPS.Task.list():
            if interest in i.name():
                r = True
        return r

    def __show_button(self):
        """Initialize buttons and parameters.
        """
        if uses_stm32f4(GPS.Project.root()):
            for b in self.__buttons:
                b.show()
        else:
            for b in self.__buttons:
                b.hide()

        # reset
        self.__connection = None

    ###############################
    # The following are workflows #
    ###############################

    def __flash_wf(self, main_name):
        """Workflow to build and flash the program on the board.
        """

        if main_name is None:
            self.__error_exit(msg="Could not find the name of the main.")
            return

        builder = promises.TargetWrapper("Build Main")
        r0 = yield builder.wait_on_execute(main_name)
        if r0 is not 0:
            self.__error_exit(msg="Build error.")
            return

        msg_is("Creating the binary (flashable) image.")
        b = GPS.Project.root().get_executable_name(GPS.File(main_name))
        d = GPS.Project.root().object_dirs()[0]
        obj = d + b
        binary = obj + ".bin"
        cmd = ["arm-eabi-objcopy", "-O", "binary", obj, binary]
        try:
            con = promises.ProcessWrapper(cmd)
        except:
            self.__error_exit("Could not launch executable arm-eabi-objcopy.")
            return

        r1 = yield con.wait_until_terminate()
        if r1 is not 0:
            self.__error_exit("arm-eabi-objcopy returned an error.")
            return

        msg_is("Flashing image to board.")
        cmd = ["st-flash", "write", binary, "0x8000000"]
        try:
            con = promises.ProcessWrapper(cmd)
        except:
            self.__error_exit("Could not connect to the board.")
            return

        r2 = yield con.wait_until_match(
            "Starting verification of write complete",
            15000)
        r3 = yield con.wait_until_match(
            "Flash written and verified! jolly good!",
            500)

        if not (r2 and r3):
            self.__error_exit(msg="Could not flash the executable.")
            con.get().kill()
            return

        msg_is("Flashing complete. You may need to reset (or cycle power).")

    def __debug_wf(self, main_name):
        """
        Workflow to build, flash and debug the program on the real board.
        """
        if main_name is None:
            self.__error_exit(msg="Main not specified")
            return

        builder = promises.TargetWrapper("Build Main")
        r0 = yield builder.wait_on_execute(main_name)
        if r0 is not 0:
            self.__error_exit("Build error.")
            return

        msg_is("Launching st-util.")
        cmd = ["st-util"]

        try:
            con = promises.ProcessWrapper(cmd)
        except:
            self.__error_exit("Could not launch st-util.")
            return

        self.__connection = con

        msg_is("Launching debugger.")
        b = GPS.Project.root().get_executable_name(GPS.File(main_name))
        debugger_promise = promises.DebuggerWrapper(GPS.File(b))
        r3 = yield debugger_promise.wait_and_send(cmd="", block=True)

        if not r3:
            self.__error_exit("Connection Lost. "
                              + "Please check the USB connection and restart.")
            r3 = yield debugger_promise.wait_and_send(cmd="", block=True)
            self.__reset_all()
            return

    def gps_started(self):
        """
        When GPS start, add button (include creteria there)
        """
        GPS.Hook("debugger_terminated").add(self.debugger_terminated)

        # Create targets * 4:
        workflows.create_target_from_workflow(
            "Flash to Board",
            "flash-to-board",
            self.__flash_wf,
            "gps-boardloading-symbolic")
        workflows.create_target_from_workflow(
            "Debug on Board",
            "debug-on-board",
            self.__debug_wf,
            "gps-boardloading-debug-symbolic")

        for tar in self.__targets:
            b = GPS.BuildTarget(tar)
            self.__buttons.append(b)

        self.__show_button()

    def project_view_changed(self):
        """
        When project view changes, add button (include cireteria there)
        """
        self.__show_button()

    def debugger_terminated(self, hookname, debugger):
        """
        When debugger terminates, kill connection.
        """
        self.__reset_all()