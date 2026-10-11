#ifndef MRUBY_PTY
#define MRUBY_PTY

#if defined(__linux__)
#include <pty.h>
#elif defined(__APPLE__)
#include <util.h>
#endif

#include <mruby.h>
#include <mruby/variable.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <signal.h>

#define MRUBY_PTY_EXEC_FAILED 127

mrb_value mrb_pty_spawn(mrb_state* mrb, mrb_value self)
{
  char* shell;
  mrb_int rows;
  mrb_int cols;
  mrb_get_args(mrb, "zii", &shell, &rows, &cols);

  struct winsize ws;
  ws.ws_row = (unsigned short)rows;
  ws.ws_col = (unsigned short)cols;
  ws.ws_xpixel = 0;
  ws.ws_ypixel = 0;

  int master_fd;
  pid_t pid = forkpty(&master_fd, NULL, NULL, &ws);
  if (pid < 0) 
  {
    mrb_raise(mrb, E_RUNTIME_ERROR, "openpty failed");
  }

  if (pid == 0)
  {
    setenv("TERM", "xterm-256color", 1);

    char* argv[] = { shell, "-i", NULL };
    execvp(shell, argv);

    _exit(MRUBY_PTY_EXEC_FAILED);
  }

  // it's go time.
  // make non blocking
  fcntl(master_fd, F_SETFL, fcntl(master_fd, F_GETFL) | O_NONBLOCK);

  struct RClass* io_class = mrb_class_get(mrb, "IO");
  mrb_value master_fd_value = mrb_int_value(mrb, master_fd);
  mrb_value pid_value = mrb_int_value(mrb, pid);

  mrb_value io_args[2] = { master_fd_value, mrb_str_new_cstr(mrb, "w+")};
  mrb_value io = mrb_obj_new(mrb, io_class, 2, io_args);
  mrb_value params[2] = {io, pid_value};
  mrb_value pty = mrb_obj_new(mrb, mrb_class_ptr(self), 2, params);

  mrb_value pty_size[4] = {mrb_int_value(mrb, rows), mrb_int_value(mrb, cols), mrb_int_value(mrb, 0), mrb_int_value(mrb, 0)};
  mrb_funcall_argv(mrb, pty, mrb_intern_lit(mrb, "set_size"), 4, pty_size);

  return pty;
}

mrb_value mrb_pty_init(mrb_state* mrb, mrb_value self)
{
  mrb_value io;
  mrb_value pid;
  mrb_get_args(mrb, "oo", &io, &pid);
  mrb_iv_set(mrb, self, mrb_intern_lit(mrb, "@io"), io);
  mrb_iv_set(mrb, self, mrb_intern_lit(mrb, "@pid"), pid);
  return self;
}

mrb_value mrb_pty_io(mrb_state* mrb, mrb_value self)
{
  return mrb_iv_get(mrb, self, mrb_intern_lit(mrb, "@io"));
}

mrb_value mrb_pty_pid(mrb_state* mrb, mrb_value self)
{
  return mrb_iv_get(mrb, self, mrb_intern_lit(mrb, "@pid"));
}

mrb_value mrb_pty_set_size(mrb_state* mrb, mrb_value self)
{
  mrb_int row;
  mrb_int col;
  mrb_int x;
  mrb_int y;

  mrb_get_args(mrb, "iiii", &row, &col, &x, &y);
  mrb_value io = mrb_iv_get(mrb, self, mrb_intern_lit(mrb, "@io"));
  int fd = mrb_int(mrb, mrb_funcall(mrb, io, "fileno", 0, NULL)); 
  struct winsize ws;
  ws.ws_row = (unsigned short)row;
  ws.ws_col = (unsigned short)col;
  ws.ws_xpixel = (unsigned short)x;
  ws.ws_ypixel = (unsigned short)y;
  int ret = ioctl(fd, TIOCSWINSZ, &ws);
  if (ret < 0) mrb_raise(mrb, E_RUNTIME_ERROR, "Can't set winsize");

  return mrb_nil_value();
}

mrb_value mrb_pty_size(mrb_state* mrb, mrb_value self)
{
  mrb_value io = mrb_iv_get(mrb, self, mrb_intern_lit(mrb, "@io"));
  int fd = mrb_int(mrb, mrb_funcall(mrb, io, "fileno", 0, NULL)); 
  struct winsize ws;
  int ret = ioctl(fd, TIOCGWINSZ, &ws);
  if (ret < 0) mrb_raise(mrb, E_RUNTIME_ERROR, "Can't get winsize");

  mrb_value ary = mrb_ary_new(mrb);
  mrb_ary_push(mrb, ary, mrb_int_value(mrb, ws.ws_row));
  mrb_ary_push(mrb, ary, mrb_int_value(mrb, ws.ws_col));
  mrb_ary_push(mrb, ary, mrb_int_value(mrb, ws.ws_xpixel));
  mrb_ary_push(mrb, ary, mrb_int_value(mrb, ws.ws_ypixel));
  return ary;
}

mrb_value mrb_pty_did_exit(mrb_state* mrb, mrb_value self)
{
  mrb_value test = mrb_iv_get(mrb, self, mrb_intern_lit(mrb, "@exit_status"));
  if (!mrb_nil_p(test)) return test;

  mrb_value pid_value = mrb_iv_get(mrb, self, mrb_intern_lit(mrb, "@pid"));
  pid_t pid = (pid_t)mrb_int(mrb, pid_value);

  int status;
  int ret = waitpid(pid, &status, WNOHANG);
  if (ret == 0 || ret == -1) return mrb_nil_value();

  int code = WIFSIGNALED(status) ? 128 + WTERMSIG(status) : WEXITSTATUS(status);

  mrb_value code_value = mrb_int_value(mrb, code);
  mrb_iv_set(mrb, self, mrb_intern_lit(mrb, "@exit_status"), code_value);
  return code_value;
}

mrb_value mrb_pty_close(mrb_state* mrb, mrb_value self)
{  
  // close fd
  mrb_value io = mrb_iv_get(mrb, self, mrb_intern_lit(mrb, "@io"));
  if (mrb_false_p(mrb_funcall(mrb, io, "closed?", 0, NULL)))
  {
    mrb_funcall(mrb, io, "close", 0, NULL);
  }

  mrb_value test = mrb_iv_get(mrb, self, mrb_intern_lit(mrb, "@exit_status"));
  if (!mrb_nil_p(test)) return test;

  mrb_value pid_value = mrb_iv_get(mrb, self, mrb_intern_lit(mrb, "@pid"));
  pid_t pid = (pid_t)mrb_int(mrb, pid_value);

  kill(pid, SIGHUP);

  return mrb_pty_did_exit(mrb, self);
}


void mrb_mruby_pty_gem_init(mrb_state *mrb) 
{
  struct RClass *pty = mrb_define_class(mrb, "PTY", mrb->object_class);
  mrb_define_class_method(mrb, pty, "spawn", mrb_pty_spawn, MRB_ARGS_REQ(3));
  mrb_define_method(mrb, pty, "initialize", mrb_pty_init, MRB_ARGS_REQ(2));
  mrb_define_method(mrb, pty, "io", mrb_pty_io, MRB_ARGS_NONE());
  mrb_define_method(mrb, pty, "pid", mrb_pty_pid, MRB_ARGS_NONE());
  mrb_define_method(mrb, pty, "set_size", mrb_pty_set_size, MRB_ARGS_REQ(4));
  mrb_define_method(mrb, pty, "size", mrb_pty_size, MRB_ARGS_NONE());
  mrb_define_method(mrb, pty, "exited?", mrb_pty_did_exit, MRB_ARGS_NONE());
  mrb_define_method(mrb, pty, "close", mrb_pty_close, MRB_ARGS_NONE());
}

void mrb_mruby_pty_gem_final(mrb_state *mrb) 
{
}
#endif