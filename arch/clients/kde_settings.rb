# YaST client: browse and launch KDE Plasma configuration modules (KCMs).
#
# Part of the YaST-on-Arch port. Plasma keeps its settings in ~133 KCMs that are
# normally reached through System Settings; this exposes them inside the YaST
# Control Center so a Plasma desktop can be administered from one place.
#
# Deliberately runs as the invoking USER, not root (X-SuSE-YaST-RootOnly=false):
# KCMs write per-user config under ~/.config, and running them as root would both
# write to the wrong home and drag a root-owned Qt/KDE cache into existence.
require "yast"
require "yast2/execute"

module Yast
  class KdeSettingsClient < Client
    include Yast::UIShortcuts
    include Yast::I18n
    include Yast::Logger

    KCMSHELL = "kcmshell6".freeze
    SYSTEMSETTINGS = "systemsettings".freeze

    def main
      textdomain "base"
      Yast.import "UI"
      Yast.import "Wizard"
      Yast.import "Popup"

      unless tool_available?(KCMSHELL)
        Popup.Error(_("KDE Plasma is not installed: '%s' was not found.") % KCMSHELL)
        return :abort
      end

      @modules = load_modules
      if @modules.empty?
        Popup.Error(_("No KDE configuration modules were found."))
        return :abort
      end

      Wizard.CreateDialog
      begin
        render
        event_loop
      ensure
        Wizard.CloseDialog
      end
      :next
    end

  private

    def tool_available?(bin)
      !Yast::Execute.locally!("sh", "-c", "command -v #{bin}", stdout: :capture).to_s.strip.empty?
    rescue StandardError
      false
    end

    # @return [Array<Hash>] {id:, description:} for every installed KCM
    def load_modules
      out = Yast::Execute.locally!(KCMSHELL, "--list", stdout: :capture).to_s
      out.lines.map do |line|
        m = line.match(/^(\S+)\s+-\s+(.*)$/)
        next unless m

        { id: m[1], description: m[2].strip }
      end.compact.sort_by { |e| e[:id] }
    rescue StandardError => e
      log.warn "kde_settings: listing modules failed: #{e.message}"
      []
    end

    def filtered
      needle = @filter.to_s.strip.downcase
      return @modules if needle.empty?

      @modules.select do |e|
        e[:id].downcase.include?(needle) || e[:description].downcase.include?(needle)
      end
    end

    def items
      filtered.map { |e| Item(Id(e[:id]), e[:id].sub(/\Akcm_/, ""), e[:description]) }
    end

    def render
      @filter ||= ""
      Wizard.SetContents(
        _("KDE Plasma Settings"),
        VBox(
          InputField(Id(:filter), Opt(:notify, :hstretch), _("&Search"), @filter),
          Table(Id(:table), Opt(:notify, :immediate),
            Header(_("Module"), _("Description")), items),
          HBox(
            PushButton(Id(:launch), _("&Open Module")),
            PushButton(Id(:all), _("Open Full &System Settings")),
            HStretch()
          )
        ),
        _("Browse the KDE Plasma configuration modules installed on this system " \
          "and open one. Modules run as your own user, not as root, because they " \
          "store their settings in your personal configuration."),
        false,
        true
      )
      UI.SetFocus(Id(:table))
    end

    def event_loop
      loop do
        event = UI.UserInput
        case event
        when :abort, :cancel, :back, :next
          break
        when :filter
          @filter = UI.QueryWidget(Id(:filter), :Value).to_s
          UI.ChangeWidget(Id(:table), :Items, items)
        when :launch, :table
          launch(UI.QueryWidget(Id(:table), :CurrentItem).to_s)
        when :all
          launch_tool(SYSTEMSETTINGS)
        end
      end
    end

    def launch(id)
      return if id.empty?

      launch_tool(KCMSHELL, id)
    end

    # Launch detached so the YaST dialog stays responsive and never blocks on a GUI.
    def launch_tool(*cmd)
      unless graphical_session?
        Popup.Error(_("A graphical session is required to open KDE settings."))
        return
      end

      pid = spawn(*cmd, out: File::NULL, err: File::NULL)
      Process.detach(pid)
      log.info "kde_settings: launched #{cmd.join(" ")} as pid #{pid}"
    rescue StandardError => e
      Popup.Error(_("Could not start %{cmd}: %{msg}") % { cmd: cmd.first, msg: e.message })
    end

    def graphical_session?
      !ENV["WAYLAND_DISPLAY"].to_s.empty? || !ENV["DISPLAY"].to_s.empty?
    end
  end
end

Yast::KdeSettingsClient.new.main
