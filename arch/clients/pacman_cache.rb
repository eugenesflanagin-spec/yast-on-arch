# Package Cache Cleaner -- yast-on-arch client (works in ncurses, Qt and GTK).
#
# Wraps paccache(8) from pacman-contrib. Runs as root through `yast -r`, so it
# needs no external helper (the Octopi cache cleaner it replaces spawned its own
# GUI and did not survive being launched from a root-side menu).
#
# Part of yast-on-arch: https://github.com/eugenesflanagin-spec/yast-on-arch
require "yast"
require "shellwords"

module Yast
  class PacmanCacheClient < Client
    include Yast::UIShortcuts
    include Yast::I18n
    include Yast::Logger

    CACHE_DIR = "/var/cache/pacman/pkg".freeze

    def main
      textdomain "base"
      Yast.import "UI"
      Yast.import "Wizard"
      Yast.import "Popup"
      Yast.import "Label"

      if `command -v paccache`.strip.empty?
        Popup.Error(_("paccache was not found. Install the 'pacman-contrib' package."))
        return :abort
      end
      unless Process.uid.zero?
        Popup.Error(_("Cleaning the package cache needs root. Start YaST with 'yast -r'."))
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

    ACTIONS = [
      # id, label, paccache args, confirmation
      [:keep3,    N_("Remove old versions, keep the 3 newest of each package"), %w[-rk3],
       N_("Delete every cached package version except the 3 newest per package?")],
      [:keep1,    N_("Remove old versions, keep only the newest of each package"), %w[-rk1],
       N_("Delete every cached package version except the newest per package?")],
      [:uninst,   N_("Remove cached packages that are no longer installed"), %w[-ruk0],
       N_("Delete all cached packages that are not installed any more?")],
      [:all,      N_("Remove every cached package (pacman -Scc)"), %w[-rk0],
       N_("Delete ALL cached packages? Reinstalling or downgrading will need a download.")],
    ].freeze

    def render
      Wizard.SetContents(
        _("Package Cache Cleaner"),
        VBox(
          Left(Label(Id(:summary), summary_text)),
          VSpacing(1),
          Left(Label(_("Choose what to remove from %s:") % CACHE_DIR)),
          RadioButtonGroup(
            Id(:action),
            VBox(*ACTIONS.map { |id, label, _a, _c| Left(RadioButton(Id(id), _(label), id == :keep3)) })
          ),
          VSpacing(1),
          HBox(
            PushButton(Id(:preview), _("&Preview")),
            PushButton(Id(:run), _("&Remove Now")),
            HStretch()
          ),
          VSpacing(1),
          MinHeight(8, LogView(Id(:log), _("paccache output"), 8, 200))
        ),
        _("<p>Old package versions accumulate in <b>%s</b>. " \
          "<b>Preview</b> shows what would be deleted; <b>Remove Now</b> deletes it. " \
          "Keeping a few old versions lets you downgrade with <tt>pacman -U</tt> offline.</p>") % CACHE_DIR,
        false, true
      )
      Wizard.SetNextButton(:next, Label.FinishButton)
      Wizard.HideBackButton
      Wizard.SetAbortButton(:abort, Label.CancelButton)
    end

    def event_loop
      loop do
        case UI.UserInput
        when :preview then run_paccache(dry: true)
        when :run     then run_paccache(dry: false)
        when :next, :abort, :cancel then return
        end
      end
    end

    def selected
      id = UI.QueryWidget(Id(:action), :CurrentButton)
      ACTIONS.find { |a| a[0] == id } || ACTIONS.first
    end

    def run_paccache(dry:)
      _id, _label, args, confirm = selected
      if !dry && !Popup.YesNo(_(confirm))
        return
      end
      cmd = ["paccache", *(dry ? args.map { |a| a.sub(/^-r/, "-d") } : args), "-c", CACHE_DIR]
      log.info "pacman_cache: #{cmd.join(' ')}"
      out = `#{Shellwords.join(cmd)} 2>&1`
      UI.ChangeWidget(Id(:log), :LastLine, "$ #{cmd.join(' ')}\n#{out}\n")
      UI.ChangeWidget(Id(:summary), :Value, summary_text)
    end

    def summary_text
      size = `du -sh #{CACHE_DIR} 2>/dev/null`.split.first || "?"
      count = Dir.glob("#{CACHE_DIR}/*.pkg.tar*").reject { |f| f.end_with?(".sig") }.size
      _("Cache: %{size} in %{count} package files") % { size: size, count: count }
    end
  end
end

Yast::PacmanCacheClient.new.main
